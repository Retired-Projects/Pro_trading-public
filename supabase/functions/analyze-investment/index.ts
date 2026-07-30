import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const allowedOrigin = Deno.env.get("ALLOWED_ORIGIN") ?? "*";
const corsHeaders = {
  "Access-Control-Allow-Origin": allowedOrigin,
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

interface TradeLog {
  stock_code: string;
  stock_name: string;
  side: "buy" | "sell";
  price: number;
  quantity: number;
  fee: number;
  tax: number;
  executed_at: string;
}

interface Holding {
  stock_code: string;
  stock_name: string;
  quantity: number;
  avg_price: number;
  current_price: number;
}

interface AnalyzeRequest {
  portfolio: {
    balance: number;
    total_asset: number;
    total_evaluation: number;
    total_pnl: number;
    holdings: Holding[];
  };
  trade_logs: TradeLog[];
}

// ── Vault 헬퍼 ────────────────────────────────────────────────────────────────

const VAULT_URL = Deno.env.get("VAULT_URL") ?? "";

function vaultHeaders() {
  const key = Deno.env.get("VAULT_SERVICE_KEY")!;
  return {
    "Content-Type": "application/json",
    "Authorization": `Bearer ${key}`,
    "apikey": key,
  };
}

async function vaultAcquire(
  model: string
): Promise<{ row_id: number; key_value: string } | null> {
  if (!VAULT_URL) return null;
  try {
    const res = await fetch(`${VAULT_URL}/rest/v1/rpc/acquire_key_slot`, {
      method: "POST",
      headers: vaultHeaders(),
      body: JSON.stringify({ p_provider: "groq", p_model: model, p_app_name: "pro-trading", p_secret: Deno.env.get("ACQUIRE_SECRET") }),
    });
    if (!res.ok) return null;
    const rows = await res.json();
    if (!Array.isArray(rows) || rows.length === 0) return null;
    return { row_id: rows[0].out_row_id, key_value: rows[0].out_key_value };
  } catch {
    return null;
  }
}

function vaultRelease(row_id: number, success: boolean, tokens: number, model?: string): void {
  fetch(`${VAULT_URL}/rest/v1/rpc/release_key_slot`, {
    method: "POST",
    headers: vaultHeaders(),
    body: JSON.stringify({ p_row_id: row_id, p_success: success, p_tokens: tokens, p_project: "pro-trading", p_model: model ?? null }),
  }).catch(() => {});
}

function vaultDeactivate(row_id: number): void {
  fetch(`${VAULT_URL}/rest/v1/rpc/deactivate_key_model`, {
    method: "POST",
    headers: vaultHeaders(),
    body: JSON.stringify({ p_row_id: row_id }),
  }).catch(() => {});
}

// ── Groq 호출 (Vault 통합, 최대 9회 429 재시도) ───────────────────────────────

async function callGroqWithVault(
  model: string,
  messages: { role: string; content: string }[],
  maxTokens: number,
  temperature: number
): Promise<{ content: string; tokens: number } | null> {
  for (let attempt = 0; attempt < 9; attempt++) {
    const slot = await vaultAcquire(model);
    if (!slot) return null;

    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), 30_000);

    let res: Response;
    try {
      res = await fetch("https://api.groq.com/openai/v1/chat/completions", {
        method: "POST",
        signal: controller.signal,
        headers: {
          Authorization: `Bearer ${slot.key_value}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ model, max_tokens: maxTokens, temperature, messages }),
      });
    } catch (err) {
      clearTimeout(timeout);
      vaultRelease(slot.row_id, false, 0, model);
      if ((err as Error).name === "AbortError") throw err;
      return null;
    } finally {
      clearTimeout(timeout);
    }

    if (res.ok) {
      const data = await res.json();
      const tokens = data.usage?.total_tokens ?? 0;
      vaultRelease(slot.row_id, true, tokens, model);
      return { content: data.choices[0].message.content as string, tokens };
    } else if (res.status === 429) {
      vaultDeactivate(slot.row_id);
      continue;
    } else {
      console.error(`analyze-investment: Groq ${model} 오류 status=${res.status}`);
      vaultRelease(slot.row_id, false, 0, model);
      return null;
    }
  }
  return null;
}

// ── 프롬프트 빌더 ─────────────────────────────────────────────────────────────

function buildPrompt(req: AnalyzeRequest): string {
  const { portfolio, trade_logs } = req;
  const initialBalance = 100_000_000;

  const totalReturn =
    ((portfolio.total_asset - initialBalance) / initialBalance) * 100;

  let winCount = 0;
  let lossCount = 0;
  let totalRealizedPnl = 0;
  let totalWinPnl = 0;
  let totalLossPnl = 0;
  const avgPriceMap: Record<string, number> = {};
  const qtyMap: Record<string, number> = {};
  const firstBuyDate: Record<string, string> = {};
  const holdingDays: number[] = [];

  const sorted = [...trade_logs].sort(
    (a, b) =>
      new Date(a.executed_at).getTime() - new Date(b.executed_at).getTime()
  );

  for (const log of sorted) {
    if (log.side === "buy") {
      const prev = avgPriceMap[log.stock_code];
      const prevQty = qtyMap[log.stock_code] ?? 0;
      if (prev !== undefined && prevQty > 0) {
        const newQty = prevQty + log.quantity;
        avgPriceMap[log.stock_code] =
          (prev * prevQty + log.price * log.quantity) / newQty;
        qtyMap[log.stock_code] = newQty;
      } else {
        avgPriceMap[log.stock_code] = log.price;
        qtyMap[log.stock_code] = log.quantity;
        firstBuyDate[log.stock_code] = log.executed_at;
      }
    } else {
      const avgBuy = avgPriceMap[log.stock_code];
      if (avgBuy !== undefined) {
        const realizedPnl =
          (log.price - avgBuy) * log.quantity - log.fee - log.tax;
        totalRealizedPnl += realizedPnl;
        if (realizedPnl > 0) {
          winCount++;
          totalWinPnl += realizedPnl;
        } else if (realizedPnl < 0) {
          lossCount++;
          totalLossPnl += Math.abs(realizedPnl);
        }
        if (firstBuyDate[log.stock_code]) {
          const buyTime = new Date(firstBuyDate[log.stock_code]).getTime();
          const sellTime = new Date(log.executed_at).getTime();
          holdingDays.push(
            Math.round((sellTime - buyTime) / (1000 * 60 * 60 * 24))
          );
        }
        const newQty = (qtyMap[log.stock_code] ?? 0) - log.quantity;
        if (newQty <= 0) {
          delete qtyMap[log.stock_code];
          delete avgPriceMap[log.stock_code];
          delete firstBuyDate[log.stock_code];
        } else {
          qtyMap[log.stock_code] = newQty;
        }
      }
    }
  }

  const totalTrades = winCount + lossCount;
  const winRate = totalTrades > 0 ? (winCount / totalTrades) * 100 : 0;
  const avgWinPnl = winCount > 0 ? totalWinPnl / winCount : 0;
  const avgLossPnl = lossCount > 0 ? totalLossPnl / lossCount : 0;
  const profitLossRatio = avgLossPnl > 0 ? avgWinPnl / avgLossPnl : 0;
  const avgHoldingDays =
    holdingDays.length > 0
      ? holdingDays.reduce((a, b) => a + b, 0) / holdingDays.length
      : 0;

  const stockFreq: Record<string, number> = {};
  for (const log of trade_logs) {
    stockFreq[log.stock_name] = (stockFreq[log.stock_name] ?? 0) + 1;
  }
  const topByFreq = Object.entries(stockFreq)
    .sort((a, b) => b[1] - a[1])
    .slice(0, 5)
    .map(([name, cnt]) => `${name}(${cnt}회)`)
    .join(", ");

  const holdingStr =
    portfolio.holdings.length === 0
      ? "없음"
      : portfolio.holdings
          .map((h) => {
            const ratio =
              portfolio.total_asset > 0
                ? ((h.current_price * h.quantity) / portfolio.total_asset) * 100
                : 0;
            const pnl =
              h.avg_price > 0
                ? ((h.current_price - h.avg_price) / h.avg_price) * 100
                : 0;
            return `  - ${h.stock_name}: ${h.quantity}주, 비중 ${ratio.toFixed(1)}%, 수익률 ${pnl.toFixed(1)}%`;
          })
          .join("\n");

  const cashRatio =
    portfolio.total_asset > 0
      ? (portfolio.balance / portfolio.total_asset) * 100
      : 100;
  const stockRatio = 100 - cashRatio;
  const buyCount = trade_logs.filter((t) => t.side === "buy").length;
  const sellCount = trade_logs.filter((t) => t.side === "sell").length;
  const maxHoldingRatio =
    portfolio.holdings.length > 0 && portfolio.total_asset > 0
      ? Math.max(
          ...portfolio.holdings.map(
            (h) => (h.current_price * h.quantity) / portfolio.total_asset
          )
        ) * 100
      : 0;

  return `당신은 모의 주식 투자 전문 분석가입니다. 아래 사용자 데이터를 바탕으로 구체적이고 전문적인 투자 리포트를 작성해주세요.
반드시 한국어로만 응답하세요. 이모지나 특수문자(*, #, -, ▶ 등)는 절대 사용하지 말고, 섹션 제목은 [제목] 형식으로만 표기하세요.

[기본 데이터]
- 초기자금: 100,000,000원
- 현재 총자산: ${portfolio.total_asset.toFixed(0)}원
- 전체 수익률: ${totalReturn >= 0 ? "+" : ""}${totalReturn.toFixed(2)}%
- 예수금(현금): ${portfolio.balance.toFixed(0)}원 (${cashRatio.toFixed(1)}%)
- 주식 평가금: ${portfolio.total_evaluation.toFixed(0)}원 (${stockRatio.toFixed(1)}%)

[매매 통계]
- 총 체결: ${trade_logs.length}회 (매수 ${buyCount}회, 매도 ${sellCount}회)
- 종결 거래: ${totalTrades}건 (수익 ${winCount}건, 손실 ${lossCount}건)
- 승률: ${totalTrades > 0 ? winRate.toFixed(1) : "0"}%
- 실현손익: ${totalRealizedPnl >= 0 ? "+" : ""}${totalRealizedPnl.toFixed(0)}원
- 평균 수익 거래 손익: +${avgWinPnl.toFixed(0)}원
- 평균 손실 거래 손익: -${avgLossPnl.toFixed(0)}원
- 손익비(평균수익/평균손실): ${profitLossRatio.toFixed(2)}
- 평균 보유기간: 약 ${avgHoldingDays.toFixed(0)}일

[보유 종목 현황] (${portfolio.holdings.length}개)
${holdingStr}
- 최대 단일 종목 비중: ${maxHoldingRatio.toFixed(1)}%

[주요 거래 종목] (빈도순)
${topByFreq || "없음"}

위 데이터를 바탕으로 반드시 아래 6개 섹션으로 리포트를 작성하세요.
각 섹션은 [섹션명] 으로 시작하고, 데이터를 근거로 구체적으로 서술하세요.

[투자 성향]
공격적/균형적/보수적 성향 판단과 근거를 2-3문장으로 서술.

[수익성 분석]
수익률, 승률, 손익비를 종합 평가. 실현손익의 의미와 현황을 2-3문장으로 서술.

[리스크 관리 평가]
현금 비중, 종목 집중도, 최대 단일 포지션 비중을 기반으로 리스크 수준을 2-3문장으로 평가.

[매매 패턴 분석]
평균 보유기간, 매수/매도 빈도, 주요 거래 종목을 바탕으로 매매 스타일을 2-3문장으로 분석.

[개선 권고사항]
가장 중요한 개선점 3가지를 번호 목록(1. 2. 3.)으로 구체적으로 작성.

[종합 의견]
전체 투자 활동에 대한 총평을 2-3문장으로 마무리.`;
}

// ── 모델 폴백 순서 ─────────────────────────────────────────────────────────────

const MODELS = [
  "llama-3.3-70b-versatile",
  "meta-llama/llama-4-scout-17b-16e-instruct",
  "llama-3.1-8b-instant",
];

// ── 핸들러 ────────────────────────────────────────────────────────────────────

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "인증 토큰이 없습니다." }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");

    if (!supabaseUrl || !supabaseAnonKey) {
      console.error("analyze-investment: 필수 환경변수 누락");
      return new Response(
        JSON.stringify({ error: "서버 설정 오류가 발생했습니다." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });

    const {
      data: { user },
      error: userError,
    } = await userClient.auth.getUser();

    if (userError || !user) {
      return new Response(
        JSON.stringify({ error: "유효하지 않은 사용자입니다." }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    let body: AnalyzeRequest;
    try {
      body = await req.json();
    } catch {
      return new Response(
        JSON.stringify({ error: "잘못된 요청 형식입니다." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (!body?.portfolio || typeof body.portfolio !== "object") {
      return new Response(
        JSON.stringify({ error: "포트폴리오 데이터가 없습니다." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    if (!Array.isArray(body.trade_logs)) {
      return new Response(
        JSON.stringify({ error: "거래 내역 데이터가 없습니다." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    if (body.trade_logs.length > 1000) {
      return new Response(
        JSON.stringify({ error: "거래 내역이 너무 많습니다." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    const p = body.portfolio;
    if (
      typeof p.balance !== "number" ||
      typeof p.total_asset !== "number" ||
      typeof p.total_evaluation !== "number" ||
      typeof p.total_pnl !== "number" ||
      !Array.isArray(p.holdings)
    ) {
      return new Response(
        JSON.stringify({ error: "포트폴리오 데이터 형식이 올바르지 않습니다." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const prompt = buildPrompt(body);
    const messages = [{ role: "user", content: prompt }];

    // Vault 키 관리 시스템을 통한 Groq 호출 (모델 폴백)
    let analysisResult: { content: string; tokens: number } | null = null;

    for (const model of MODELS) {
      try {
        analysisResult = await callGroqWithVault(model, messages, 1200, 0.4);
      } catch (err) {
        if ((err as Error).name === "AbortError") {
          return new Response(
            JSON.stringify({ error: "AI 분석 시간이 초과되었습니다. 잠시 후 다시 시도해주세요." }),
            { status: 504, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          );
        }
        throw err;
      }
      if (analysisResult) break;
    }

    if (!analysisResult) {
      console.error("analyze-investment: 모든 모델 슬롯 소진 또는 오류");
      return new Response(
        JSON.stringify({ error: "AI 서비스가 일시적으로 사용 불가합니다. 잠시 후 다시 시도해주세요." }),
        { status: 503, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const analysis = analysisResult.content;

    // 리포트 저장 (당일 upsert)
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseServiceKey) {
      console.error("analyze-investment: SERVICE_ROLE_KEY 누락 — 리포트 저장 건너뜀");
      return new Response(JSON.stringify({ analysis }), {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const adminClient = createClient(supabaseUrl, supabaseServiceKey);
    const today = new Date().toISOString().split("T")[0];
    const initialBalance = 100_000_000;
    const totalReturn =
      ((body.portfolio.total_asset - initialBalance) / initialBalance) * 100;

    await adminClient.from("ai_reports").upsert(
      {
        user_id: user.id,
        report_date: today,
        content: analysis,
        trade_count: body.trade_logs.length,
        total_asset: body.portfolio.total_asset,
        total_return: Math.round(totalReturn * 100) / 100,
      },
      { onConflict: "user_id,report_date" }
    );

    return new Response(JSON.stringify({ analysis }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    console.error("analyze-investment: 예상치 못한 오류", err);
    return new Response(
      JSON.stringify({ error: "분석 중 오류가 발생했습니다. 잠시 후 다시 시도해주세요." }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
