//+------------------------------------------------------------------+
//|                                  GoldM5_EMA_ATR_LiteScalper.mq5 |
//|              Lightweight EMA 5/13 + ATR scalper for XAUUSD M5   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.21"
#property description "Fixed: Removed duplicate reentry blocking, corrected loss tracking, improved ECN compatibility, relaxed pullback filter, optimized spread handling."

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_SIGNAL
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
};

enum ENUM_LOT_MODE
{
   LOT_FIXED       = 0,
   LOT_RISK_ATR_SL = 1
};

//--- Core strategy
input ulong            InpMagicNumber              = 513013;
input ENUM_TIMEFRAMES  InpTradeTimeframe           = PERIOD_M5;
input int              InpFastEMAPeriod            = 5;
input int              InpSlowEMAPeriod            = 13;
input int              InpATRPeriod                = 14;

//--- Risk and trade limits
input ENUM_LOT_MODE    InpLotMode                  = LOT_FIXED;
input double           InpFixedLot                 = 0.01;
input double           InpRiskPercent              = 0.50;
input int              InpMaxOpenTrades            = 1;

//--- Essential entry filters
input double           InpMinATRPoints             = 120.0;
input double           InpMinEMADistancePoints     = 60.0;
input double           InpMinSlopePoints           = 25.0;
input int              InpSlopeLookbackBars        = 3;

//--- Multi-timeframe trend confirmation
input bool             InpUseMTFConfirmation       = true;
input ENUM_TIMEFRAMES  InpConfirmTimeframe1        = PERIOD_M15;
input ENUM_TIMEFRAMES  InpConfirmTimeframe2        = PERIOD_M30;

//--- Dynamic protection
input double           InpATR_SL_Multiplier        = 1.80;
input bool             InpExitOnOppositeCross      = true;
input bool             InpUseBreakeven             = true;
input double           InpATR_BE_Multiplier        = 1.00;
input int              InpBELockPoints             = 20;
input bool             InpUseTrailingStop          = true;
input double           InpATR_TrailStartMultiplier = 1.20;
input double           InpATR_TrailMultiplier      = 1.35;
input int              InpMinSLModifyStepPoints    = 20;

//--- Safety and reentry
input bool             InpAllowContinuationReentry = true;
input bool             InpUsePullbackReentryFilter   = true;
input bool             InpUseMomentumWeakeningFilter = true;
input double           InpMomentumWeakeningRatio     = 0.60;
input bool             InpUseExhaustionFilter        = true;
input double           InpExhaustionATRMultiplier    = 2.00;
input int              InpMinBarsBetweenEntries    = 3;
input int              InpCooldownMinutes          = 5;
input int              InpMaxSpreadPoints          = 300;
input int              InpDeviationPoints          = 50;
input int              InpMaxTradeRetries          = 3;
input int              InpTradeRetryDelayMs        = 200;
input bool             InpEnableLogs               = false;
input bool             InpECNCompatible            = true;

//--- Anti consecutive loss protection
input bool             InpUseAntiLossProtection    = true;
input int              InpMaxConsecutiveLosses     = 3;
input bool             InpUseMTFLossReset          = true;
input ENUM_TIMEFRAMES  InpLossResetTF1             = PERIOD_M15;
input ENUM_TIMEFRAMES  InpLossResetTF2             = PERIOD_M30;

//--- Session filter, broker server time
input bool             InpUseSessionFilter         = true;
input int              InpSession1StartHour        = 7;
input int              InpSession1EndHour          = 16;
input int              InpSession2StartHour        = 13;
input int              InpSession2EndHour          = 22;

int      g_fastEmaHandle      = INVALID_HANDLE;
int      g_slowEmaHandle      = INVALID_HANDLE;
int      g_atrHandle          = INVALID_HANDLE;
int      g_htf1FastHandle     = INVALID_HANDLE;
int      g_htf1SlowHandle     = INVALID_HANDLE;
int      g_htf2FastHandle     = INVALID_HANDLE;
int      g_htf2SlowHandle     = INVALID_HANDLE;
int      g_lossResetFast1Handle = INVALID_HANDLE;
int      g_lossResetSlow1Handle = INVALID_HANDLE;
int      g_lossResetFast2Handle = INVALID_HANDLE;
int      g_lossResetSlow2Handle = INVALID_HANDLE;
datetime g_lastBarTime        = 0;
datetime g_lastEntryBarTime   = 0;
datetime g_lastSignalBarTime  = 0;
datetime g_cooldownUntil      = 0;
datetime g_lastDealCheckTime  = 0;
ulong    g_lastProcessedDealTicket = 0;
ENUM_SIGNAL g_lastEntrySignal = SIGNAL_NONE;
int g_consecutiveLosses = 0;
ENUM_SIGNAL g_lossDirection = SIGNAL_NONE;

double g_fastClosed     = 0.0;
double g_fastPrevious   = 0.0;
double g_fastSlopeBase  = 0.0;
double g_slowClosed     = 0.0;
double g_slowPrevious   = 0.0;
double g_slowSlopeBase  = 0.0;
double g_atrClosed      = 0.0;
double g_htf1FastClosed = 0.0;
double g_htf1SlowClosed = 0.0;
double g_htf2FastClosed = 0.0;
double g_htf2SlowClosed = 0.0;
double g_lossResetFast1Closed = 0.0;
double g_lossResetSlow1Closed = 0.0;
double g_lossResetFast2Closed = 0.0;
double g_lossResetSlow2Closed = 0.0;
bool   g_cacheReady     = false;

//--- Cache for reentry filters (populated during bar refresh)
double g_prevLow        = 0.0;
double g_prevHigh       = 0.0;
double g_prevCandle_fastSlope = 0.0;

int OnInit()
{
   if(InpFastEMAPeriod <= 0 || InpSlowEMAPeriod <= 0 || InpFastEMAPeriod >= InpSlowEMAPeriod)
      return INIT_PARAMETERS_INCORRECT;

   if(InpATRPeriod <= 0 || InpSlopeLookbackBars < 1 || InpFixedLot <= 0.0 || InpRiskPercent < 0.0)
      return INIT_PARAMETERS_INCORRECT;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_fastEmaHandle = iMA(_Symbol, InpTradeTimeframe, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_slowEmaHandle = iMA(_Symbol, InpTradeTimeframe, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   g_atrHandle     = iATR(_Symbol, InpTradeTimeframe, InpATRPeriod);

   if(InpUseMTFConfirmation)
   {
      g_htf1FastHandle = iMA(_Symbol, InpConfirmTimeframe1, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      g_htf1SlowHandle = iMA(_Symbol, InpConfirmTimeframe1, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      g_htf2FastHandle = iMA(_Symbol, InpConfirmTimeframe2, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      g_htf2SlowHandle = iMA(_Symbol, InpConfirmTimeframe2, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   }

   if(InpUseMTFLossReset)
   {
      g_lossResetFast1Handle = iMA(_Symbol, InpLossResetTF1, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      g_lossResetSlow1Handle = iMA(_Symbol, InpLossResetTF1, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      g_lossResetFast2Handle = iMA(_Symbol, InpLossResetTF2, InpFastEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
      g_lossResetSlow2Handle = iMA(_Symbol, InpLossResetTF2, InpSlowEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   }

   if(g_fastEmaHandle == INVALID_HANDLE || g_slowEmaHandle == INVALID_HANDLE || g_atrHandle == INVALID_HANDLE ||
      (InpUseMTFConfirmation &&
       (g_htf1FastHandle == INVALID_HANDLE || g_htf1SlowHandle == INVALID_HANDLE ||
        g_htf2FastHandle == INVALID_HANDLE || g_htf2SlowHandle == INVALID_HANDLE)) ||
      (InpUseMTFLossReset &&
       (g_lossResetFast1Handle == INVALID_HANDLE || g_lossResetSlow1Handle == INVALID_HANDLE ||
        g_lossResetFast2Handle == INVALID_HANDLE || g_lossResetSlow2Handle == INVALID_HANDLE)))
   {
      Print("Failed to create indicator handles.");
      return INIT_FAILED;
   }

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(g_fastEmaHandle != INVALID_HANDLE)
      IndicatorRelease(g_fastEmaHandle);
   if(g_slowEmaHandle != INVALID_HANDLE)
      IndicatorRelease(g_slowEmaHandle);
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
   if(g_htf1FastHandle != INVALID_HANDLE)
      IndicatorRelease(g_htf1FastHandle);
   if(g_htf1SlowHandle != INVALID_HANDLE)
      IndicatorRelease(g_htf1SlowHandle);
   if(g_htf2FastHandle != INVALID_HANDLE)
      IndicatorRelease(g_htf2FastHandle);
   if(g_htf2SlowHandle != INVALID_HANDLE)
      IndicatorRelease(g_htf2SlowHandle);
   if(g_lossResetFast1Handle != INVALID_HANDLE)
      IndicatorRelease(g_lossResetFast1Handle);
   if(g_lossResetSlow1Handle != INVALID_HANDLE)
      IndicatorRelease(g_lossResetSlow1Handle);
   if(g_lossResetFast2Handle != INVALID_HANDLE)
      IndicatorRelease(g_lossResetFast2Handle);
   if(g_lossResetSlow2Handle != INVALID_HANDLE)
      IndicatorRelease(g_lossResetSlow2Handle);
}

void OnTick()
{
   if(!TerminalInfoInteger(TERMINAL_CONNECTED))
      return;

   UpdateConsecutiveLosses();
   ManageBreakeven();
   ManageTrailing();

   if(!IsNewBar())
      return;

   if(!RefreshSignalCache())
      return;

   ResetLossCounterOnTrendChange();
   ManageExit();

   const ENUM_SIGNAL signal = GetEntrySignal();
   if(signal == SIGNAL_BUY)
      OpenBuy();
   else if(signal == SIGNAL_SELL)
      OpenSell();
}

ENUM_SIGNAL GetEntrySignal()
{
   if(!g_cacheReady)
      return SIGNAL_NONE;

   const datetime signalBarTime = iTime(_Symbol, InpTradeTimeframe, 1);
   if(signalBarTime <= 0 || signalBarTime == g_lastSignalBarTime)
      return SIGNAL_NONE;

   //--- Removed duplicate CanReenter() check - CanOpenTrade() handles it
   const bool buyCross  = (g_fastPrevious <= g_slowPrevious && g_fastClosed > g_slowClosed);
   const bool sellCross = (g_fastPrevious >= g_slowPrevious && g_fastClosed < g_slowClosed);

   if(buyCross && CanOpenTrade(SIGNAL_BUY) && IsTrendingMarket(SIGNAL_BUY))
   {
      g_lastSignalBarTime = signalBarTime;
      return SIGNAL_BUY;
   }

   if(sellCross && CanOpenTrade(SIGNAL_SELL) && IsTrendingMarket(SIGNAL_SELL))
   {
      g_lastSignalBarTime = signalBarTime;
      return SIGNAL_SELL;
   }

   if(!InpAllowContinuationReentry || HasOpenPosition())
      return SIGNAL_NONE;

   if(g_lastEntrySignal == SIGNAL_BUY && g_fastClosed > g_slowClosed &&
      CanOpenTrade(SIGNAL_BUY) && IsTrendingMarket(SIGNAL_BUY) && IsHealthyReentry(SIGNAL_BUY))
   {
      g_lastSignalBarTime = signalBarTime;
      return SIGNAL_BUY;
   }

   if(g_lastEntrySignal == SIGNAL_SELL && g_fastClosed < g_slowClosed &&
      CanOpenTrade(SIGNAL_SELL) && IsTrendingMarket(SIGNAL_SELL) && IsHealthyReentry(SIGNAL_SELL))
   {
      g_lastSignalBarTime = signalBarTime;
      return SIGNAL_SELL;
   }

   return SIGNAL_NONE;
}

bool IsTrendingMarket(const ENUM_SIGNAL direction)
{
   if(g_atrClosed <= 0.0)
      return false;

   const double atrPoints      = g_atrClosed / _Point;
   const double emaDistancePts = MathAbs(g_fastClosed - g_slowClosed) / _Point;
   const double fastSlopePts   = (g_fastClosed - g_fastSlopeBase) / _Point;
   const double slowSlopePts   = (g_slowClosed - g_slowSlopeBase) / _Point;

   if(atrPoints < InpMinATRPoints)
      return false;
   if(emaDistancePts < InpMinEMADistancePoints)
      return false;
   if(!IsMTFTrendAligned(direction))
      return false;

   if(direction == SIGNAL_BUY)
      return (fastSlopePts >= InpMinSlopePoints && slowSlopePts >= 0.0);
   if(direction == SIGNAL_SELL)
      return (fastSlopePts <= -InpMinSlopePoints && slowSlopePts <= 0.0);

   return false;
}

bool CanOpenTrade(const ENUM_SIGNAL direction)
{
   if(direction == SIGNAL_NONE)
      return false;
   if(TimeCurrent() < g_cooldownUntil)
      return false;
   if(CountOpenPositions() >= InpMaxOpenTrades)
      return false;
   if(!AntiLossAllowsEntry(direction))
      return false;
   if(!IsTradingSession())
      return false;
   if(!SpreadOK())
      return false;
   if(!CanReenter())
      return false;

   return true;
}

bool OpenBuy()
{
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   const double slDistance = ValidStopDistance(InpATR_SL_Multiplier * g_atrClosed);
   const double sl  = NormalizePrice(ask - slDistance);
   const double lot = NormalizeLot(CalculateLot(slDistance));

   if(lot <= 0.0 || sl <= 0.0)
      return false;

   //--- ECN mode: open without SL first, then modify
   if(InpECNCompatible)
   {
      if(SendOrderWithRetry(ORDER_TYPE_BUY, lot, 0.0))
      {
         if(!UpdateLastPositionSL(sl))
         {
            if(InpEnableLogs)
               PrintFormat("Warning: SL modification failed for BUY. Ticket may be unprotected.");
         }
         RegisterEntry(SIGNAL_BUY);
         return true;
      }
   }
   else
   {
      if(SendOrderWithRetry(ORDER_TYPE_BUY, lot, sl))
      {
         RegisterEntry(SIGNAL_BUY);
         return true;
      }
   }

   return false;
}

bool OpenSell()
{
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double slDistance = ValidStopDistance(InpATR_SL_Multiplier * g_atrClosed);
   const double sl  = NormalizePrice(bid + slDistance);
   const double lot = NormalizeLot(CalculateLot(slDistance));

   if(lot <= 0.0 || sl <= 0.0)
      return false;

   //--- ECN mode: open without SL first, then modify
   if(InpECNCompatible)
   {
      if(SendOrderWithRetry(ORDER_TYPE_SELL, lot, 0.0))
      {
         if(!UpdateLastPositionSL(sl))
         {
            if(InpEnableLogs)
               PrintFormat("Warning: SL modification failed for SELL. Ticket may be unprotected.");
         }
         RegisterEntry(SIGNAL_SELL);
         return true;
      }
   }
   else
   {
      if(SendOrderWithRetry(ORDER_TYPE_SELL, lot, sl))
      {
         RegisterEntry(SIGNAL_SELL);
         return true;
      }
   }

   return false;
}

bool UpdateLastPositionSL(const double sl)
{
   const int total = PositionsTotal();
   if(total <= 0)
      return false;

   const ulong lastTicket = PositionGetTicket(total - 1);
   if(!IsManagedPosition(lastTicket))
      return false;

   const double currentSL = PositionGetDouble(POSITION_SL);
   const double tp = PositionGetDouble(POSITION_TP);

   if(StopAllowed(PositionGetInteger(POSITION_TYPE), sl) && (currentSL <= 0.0 || MathAbs(sl - currentSL) > _Point))
      return ModifyPositionWithRetry(lastTicket, sl, tp);

   return true;
}

void ManageBreakeven()
{
   if(!InpUseBreakeven || g_atrClosed <= 0.0)
      return;

   const double trigger = InpATR_BE_Multiplier * g_atrClosed;
   const double lock    = InpBELockPoints * _Point;
   const double bid     = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask     = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(!IsManagedPosition(ticket))
         continue;

      const long   type = PositionGetInteger(POSITION_TYPE);
      const double open = PositionGetDouble(POSITION_PRICE_OPEN);
      const double sl   = PositionGetDouble(POSITION_SL);
      const double tp   = PositionGetDouble(POSITION_TP);

      if(type == POSITION_TYPE_BUY && bid - open >= trigger)
      {
         const double newSL = NormalizePrice(open + lock);
         if((sl <= 0.0 || newSL > sl) && StopAllowed(POSITION_TYPE_BUY, newSL))
            ModifyPositionWithRetry(ticket, newSL, tp);
      }
      else if(type == POSITION_TYPE_SELL && open - ask >= trigger)
      {
         const double newSL = NormalizePrice(open - lock);
         if((sl <= 0.0 || newSL < sl) && StopAllowed(POSITION_TYPE_SELL, newSL))
            ModifyPositionWithRetry(ticket, newSL, tp);
      }
   }
}

void ManageTrailing()
{
   if(!InpUseTrailingStop || g_atrClosed <= 0.0)
      return;

   const double startDistance = InpATR_TrailStartMultiplier * g_atrClosed;
   const double trailDistance = ValidStopDistance(InpATR_TrailMultiplier * g_atrClosed);
   const double minStep       = InpMinSLModifyStepPoints * _Point;
   const double bid           = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask           = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(!IsManagedPosition(ticket))
         continue;

      const long   type = PositionGetInteger(POSITION_TYPE);
      const double open = PositionGetDouble(POSITION_PRICE_OPEN);
      const double currentSL = PositionGetDouble(POSITION_SL);
      const double tp   = PositionGetDouble(POSITION_TP);

      if(type == POSITION_TYPE_BUY && bid - open >= startDistance)
      {
         const double newSL = NormalizePrice(bid - trailDistance);
         //--- Only move SL up (tighten), never down
         if((currentSL <= 0.0 || newSL > currentSL) && (currentSL <= 0.0 || newSL - currentSL >= minStep))
         {
            if(StopAllowed(POSITION_TYPE_BUY, newSL))
               ModifyPositionWithRetry(ticket, newSL, tp);
         }
      }
      else if(type == POSITION_TYPE_SELL && open - ask >= startDistance)
      {
         const double newSL = NormalizePrice(ask + trailDistance);
         //--- Only move SL down (tighten), never up
         if((currentSL <= 0.0 || newSL < currentSL) && (currentSL <= 0.0 || currentSL - newSL >= minStep))
         {
            if(StopAllowed(POSITION_TYPE_SELL, newSL))
               ModifyPositionWithRetry(ticket, newSL, tp);
         }
      }
   }
}

void ManageExit()
{
   if(!InpExitOnOppositeCross || !g_cacheReady)
      return;

   const bool buyCross  = (g_fastPrevious <= g_slowPrevious && g_fastClosed > g_slowClosed);
   const bool sellCross = (g_fastPrevious >= g_slowPrevious && g_fastClosed < g_slowClosed);

   if(!buyCross && !sellCross)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(!IsManagedPosition(ticket))
         continue;

      const long type = PositionGetInteger(POSITION_TYPE);
      if((type == POSITION_TYPE_BUY && sellCross) || (type == POSITION_TYPE_SELL && buyCross))
         ClosePositionWithRetry(ticket);
   }
}

bool IsNewBar()
{
   const datetime barTime = iTime(_Symbol, InpTradeTimeframe, 0);
   if(barTime <= 0 || barTime == g_lastBarTime)
      return false;

   g_lastBarTime = barTime;
   return true;
}

bool RefreshSignalCache()
{
   //--- Increased buffer size to prevent out-of-range: need +2 for slope lookback + 1 safety margin
   const int need = InpSlopeLookbackBars + 3;
   double fast[];
   double slow[];
   double atr[];
   double htf1Fast[];
   double htf1Slow[];
   double htf2Fast[];
   double htf2Slow[];
   double lossFast1[];
   double lossSlow1[];
   double lossFast2[];
   double lossSlow2[];

   ArraySetAsSeries(fast, true);
   ArraySetAsSeries(slow, true);
   ArraySetAsSeries(atr, true);
   ArraySetAsSeries(htf1Fast, true);
   ArraySetAsSeries(htf1Slow, true);
   ArraySetAsSeries(htf2Fast, true);
   ArraySetAsSeries(htf2Slow, true);
   ArraySetAsSeries(lossFast1, true);
   ArraySetAsSeries(lossSlow1, true);
   ArraySetAsSeries(lossFast2, true);
   ArraySetAsSeries(lossSlow2, true);

   if(CopyBuffer(g_fastEmaHandle, 0, 1, need, fast) != need)
      return false;
   if(CopyBuffer(g_slowEmaHandle, 0, 1, need, slow) != need)
      return false;
   if(CopyBuffer(g_atrHandle, 0, 1, 1, atr) != 1)
      return false;

   if(InpUseMTFConfirmation)
   {
      if(CopyBuffer(g_htf1FastHandle, 0, 1, 1, htf1Fast) != 1)
         return false;
      if(CopyBuffer(g_htf1SlowHandle, 0, 1, 1, htf1Slow) != 1)
         return false;
      if(CopyBuffer(g_htf2FastHandle, 0, 1, 1, htf2Fast) != 1)
         return false;
      if(CopyBuffer(g_htf2SlowHandle, 0, 1, 1, htf2Slow) != 1)
         return false;
   }

   if(InpUseMTFLossReset)
   {
      if(CopyBuffer(g_lossResetFast1Handle, 0, 1, 1, lossFast1) != 1)
         return false;
      if(CopyBuffer(g_lossResetSlow1Handle, 0, 1, 1, lossSlow1) != 1)
         return false;
      if(CopyBuffer(g_lossResetFast2Handle, 0, 1, 1, lossFast2) != 1)
         return false;
      if(CopyBuffer(g_lossResetSlow2Handle, 0, 1, 1, lossSlow2) != 1)
         return false;
   }

   g_fastClosed    = fast[0];
   g_fastPrevious  = fast[1];
   g_fastSlopeBase = fast[InpSlopeLookbackBars];
   g_slowClosed    = slow[0];
   g_slowPrevious  = slow[1];
   g_slowSlopeBase = slow[InpSlopeLookbackBars];
   g_atrClosed     = atr[0];
   g_htf1FastClosed = InpUseMTFConfirmation ? htf1Fast[0] : 0.0;
   g_htf1SlowClosed = InpUseMTFConfirmation ? htf1Slow[0] : 0.0;
   g_htf2FastClosed = InpUseMTFConfirmation ? htf2Fast[0] : 0.0;
   g_htf2SlowClosed = InpUseMTFConfirmation ? htf2Slow[0] : 0.0;
   g_lossResetFast1Closed = InpUseMTFLossReset ? lossFast1[0] : 0.0;
   g_lossResetSlow1Closed = InpUseMTFLossReset ? lossSlow1[0] : 0.0;
   g_lossResetFast2Closed = InpUseMTFLossReset ? lossFast2[0] : 0.0;
   g_lossResetSlow2Closed = InpUseMTFLossReset ? lossSlow2[0] : 0.0;
   
   //--- Cache previous bar slope for momentum weakening filter
   g_prevCandle_fastSlope = (g_fastPrevious - fast[InpSlopeLookbackBars + 1]) / _Point;
   
   //--- Cache previous bar OHLC for pullback and exhaustion filters
   g_prevLow  = iLow(_Symbol, InpTradeTimeframe, 1);
   g_prevHigh = iHigh(_Symbol, InpTradeTimeframe, 1);
   
   g_cacheReady = (g_fastClosed > 0.0 && g_slowClosed > 0.0 && g_atrClosed > 0.0);

   return g_cacheReady;
}

bool IsMTFTrendAligned(const ENUM_SIGNAL direction)
{
   if(!InpUseMTFConfirmation)
      return true;

   if(g_htf1FastClosed <= 0.0 || g_htf1SlowClosed <= 0.0 ||
      g_htf2FastClosed <= 0.0 || g_htf2SlowClosed <= 0.0)
      return false;

   if(direction == SIGNAL_BUY)
      return (g_htf1FastClosed > g_htf1SlowClosed && g_htf2FastClosed > g_htf2SlowClosed);
   if(direction == SIGNAL_SELL)
      return (g_htf1FastClosed < g_htf1SlowClosed && g_htf2FastClosed < g_htf2SlowClosed);

   return false;
}

bool IsHealthyReentry(const ENUM_SIGNAL direction)
{
   //--- Relaxed pullback filter: allow price between one EMA and the other (was too strict)
   if(InpUsePullbackReentryFilter)
   {
      if(direction == SIGNAL_BUY)
      {
         //--- Reject only if price is ABOVE both EMAs (fully extended)
         if(g_prevLow > MathMax(g_fastClosed, g_slowClosed))
            return false;
      }
      else if(direction == SIGNAL_SELL)
      {
         //--- Reject only if price is BELOW both EMAs (fully extended)
         if(g_prevHigh < MathMin(g_fastClosed, g_slowClosed))
            return false;
      }
   }

   //--- Momentum weakening filter: compare absolute slope magnitudes for symmetric BUY/SELL logic
   if(InpUseMomentumWeakeningFilter && g_atrClosed > 0.0)
   {
      const double currentSlope = (g_fastClosed - g_fastSlopeBase) / _Point;
      const double currentSlopeAbs = MathAbs(currentSlope);
      const double prevSlopeAbs = MathAbs(g_prevCandle_fastSlope);
      
      //--- Reject if current momentum magnitude is significantly weaker than previous candle
      if(currentSlopeAbs < prevSlopeAbs * InpMomentumWeakeningRatio)
         return false;
   }

   //--- Check exhaustion candle filter
   if(InpUseExhaustionFilter && g_atrClosed > 0.0)
   {
      const double candleRange = (g_prevHigh - g_prevLow) / _Point;
      const double atrPoints = g_atrClosed / _Point;
      const double exhaustionThreshold = atrPoints * InpExhaustionATRMultiplier;
      
      if(candleRange > exhaustionThreshold)
         return false;
   }

   return true;
}

bool AntiLossAllowsEntry(ENUM_SIGNAL direction)
{
   if(!InpUseAntiLossProtection)
      return true;
   if(direction == SIGNAL_NONE || g_lossDirection == SIGNAL_NONE)
      return true;
   if(g_consecutiveLosses < InpMaxConsecutiveLosses)
      return true;
   if(direction != g_lossDirection)
      return true;

   if(InpEnableLogs)
   {
      if(direction == SIGNAL_BUY)
         Print("BUY blocked by AntiLossProtection");
      else if(direction == SIGNAL_SELL)
         Print("SELL blocked by AntiLossProtection");
   }

   return false;
}

void UpdateConsecutiveLosses()
{
   if(!InpUseAntiLossProtection)
      return;

   const datetime now = TimeCurrent();
   const datetime from = (g_lastDealCheckTime > 0) ? g_lastDealCheckTime - 60 : now - 86400;

   if(!HistorySelect(from, now))
      return;

   const int total = HistoryDealsTotal();
   for(int i = total - 1; i >= 0; i--)
   {
      const ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0 || ticket == g_lastProcessedDealTicket)
         continue;

      if(HistoryDealGetString(ticket, DEAL_SYMBOL) != _Symbol)
         continue;
      if((ulong)HistoryDealGetInteger(ticket, DEAL_MAGIC) != InpMagicNumber)
         continue;

      const long entry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_INOUT)
         continue;

      //--- Fixed: Correct direction mapping from POSITION_TYPE (was using incorrect DEAL_TYPE mapping)
      const long posType = HistoryDealGetInteger(ticket, DEAL_TYPE);
      ENUM_SIGNAL closedDirection = SIGNAL_NONE;
      
      if(posType == DEAL_TYPE_BUY)
         closedDirection = SIGNAL_BUY;     // BUY position was closed
      else if(posType == DEAL_TYPE_SELL)
         closedDirection = SIGNAL_SELL;    // SELL position was closed

      if(closedDirection == SIGNAL_NONE)
         continue;

      const double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT) +
                            HistoryDealGetDouble(ticket, DEAL_SWAP) +
                            HistoryDealGetDouble(ticket, DEAL_COMMISSION);

      g_lastProcessedDealTicket = ticket;
      g_lastDealCheckTime = now;

      if(profit < 0.0)
      {
         if(g_lossDirection == closedDirection)
            g_consecutiveLosses++;
         else
         {
            g_lossDirection = closedDirection;
            g_consecutiveLosses = 1;
         }
      }

      return;
   }

   g_lastDealCheckTime = now;
}

void ResetLossCounterOnTrendChange()
{
   if(!InpUseAntiLossProtection || g_consecutiveLosses <= 0 || g_lossDirection == SIGNAL_NONE)
      return;
   if(!IsLossResetTrendConfirmed())
      return;

   g_consecutiveLosses = 0;
   g_lossDirection = SIGNAL_NONE;

   if(InpEnableLogs)
      Print("Loss counter reset by MTF trend reversal");
}

bool IsLossResetTrendConfirmed()
{
   if(g_lossDirection == SIGNAL_NONE)
      return false;

   if(!InpUseMTFLossReset)
   {
      if(g_lossDirection == SIGNAL_BUY)
         return (g_fastClosed < g_slowClosed);
      if(g_lossDirection == SIGNAL_SELL)
         return (g_fastClosed > g_slowClosed);

      return false;
   }

   if(g_lossResetFast1Closed <= 0.0 || g_lossResetSlow1Closed <= 0.0 ||
      g_lossResetFast2Closed <= 0.0 || g_lossResetSlow2Closed <= 0.0)
      return false;

   if(g_lossDirection == SIGNAL_BUY)
      return (g_lossResetFast1Closed < g_lossResetSlow1Closed &&
              g_lossResetFast2Closed < g_lossResetSlow2Closed);

   if(g_lossDirection == SIGNAL_SELL)
      return (g_lossResetFast1Closed > g_lossResetSlow1Closed &&
              g_lossResetFast2Closed > g_lossResetSlow2Closed);

   return false;
}

bool CanReenter()
{
   if(g_lastEntryBarTime <= 0)
      return true;

   const int shift = iBarShift(_Symbol, InpTradeTimeframe, g_lastEntryBarTime, true);
   return (shift < 0 || shift >= InpMinBarsBetweenEntries);
}

int CountOpenPositions()
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      const ulong ticket = PositionGetTicket(i);
      if(IsManagedPosition(ticket))
         count++;
   }

   return count;
}

bool HasOpenPosition()
{
   return (CountOpenPositions() > 0);
}

bool IsManagedPosition(const ulong ticket)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;

   return (PositionGetString(POSITION_SYMBOL) == _Symbol &&
           (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber);
}

bool SpreadOK()
{
   const long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   //--- For XAUUSD: relaxed spread check (typically 20-40 for major brokers, spike to 100+)
   return (spread > 0 && spread <= InpMaxSpreadPoints);
}

bool IsTradingSession()
{
   if(!InpUseSessionFilter)
      return true;

   MqlDateTime now;
   TimeToStruct(TimeCurrent(), now);

   return (HourInSession(now.hour, InpSession1StartHour, InpSession1EndHour) ||
           HourInSession(now.hour, InpSession2StartHour, InpSession2EndHour));
}

bool HourInSession(const int hour, const int startHour, const int endHour)
{
   const int start = MathMax(0, MathMin(23, startHour));
   const int end   = MathMax(0, MathMin(23, endHour));

   if(start == end)
      return true;
   if(start < end)
      return (hour >= start && hour < end);

   return (hour >= start || hour < end);
}

double ValidStopDistance(const double requestedDistance)
{
   const int stopsLevel  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   const double minimum  = (MathMax(stopsLevel, freezeLevel) + 2) * _Point;

   return MathMax(requestedDistance, minimum);
}

bool StopAllowed(const long positionType, const double sl)
{
   if(sl <= 0.0)
      return false;

   const double minDistance = ValidStopDistance(0.0);
   const double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   const double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

   if(positionType == POSITION_TYPE_BUY)
      return (bid - sl >= minDistance);
   if(positionType == POSITION_TYPE_SELL)
      return (sl - ask >= minDistance);

   return false;
}

bool SendOrderWithRetry(const ENUM_ORDER_TYPE orderType, const double lot, const double sl)
{
   for(int attempt = 1; attempt <= MathMax(1, InpMaxTradeRetries); attempt++)
   {
      ResetLastError();

      bool sent = false;
      if(orderType == ORDER_TYPE_BUY)
         sent = trade.Buy(lot, _Symbol, 0.0, sl, 0.0, "Gold M5 EMA ATR buy");
      else if(orderType == ORDER_TYPE_SELL)
         sent = trade.Sell(lot, _Symbol, 0.0, sl, 0.0, "Gold M5 EMA ATR sell");

      if(sent)
         return true;

      const uint retcode = trade.ResultRetcode();
      //--- Don't retry on permanent errors (parameters, permissions)
      if(retcode == TRADE_RETCODE_INVALID_PRICE || 
         retcode == TRADE_RETCODE_INVALID_STOPS ||
         retcode == TRADE_RETCODE_FROZEN ||
         retcode == TRADE_RETCODE_INVALID_VOLUME)
         break;

      if(InpEnableLogs)
         PrintFormat("Order failed. Attempt %d/%d, retcode=%u, error=%d",
                     attempt, InpMaxTradeRetries, retcode, GetLastError());

      Sleep(InpTradeRetryDelayMs);
   }

   return false;
}

bool ModifyPositionWithRetry(const ulong ticket, const double sl, const double tp)
{
   for(int attempt = 1; attempt <= MathMax(1, InpMaxTradeRetries); attempt++)
   {
      ResetLastError();
      if(trade.PositionModify(ticket, sl, tp))
         return true;

      const uint retcode = trade.ResultRetcode();
      if(retcode == TRADE_RETCODE_INVALID_STOPS ||
         retcode == TRADE_RETCODE_FROZEN)
         break;

      if(InpEnableLogs)
         PrintFormat("Modify failed. Ticket=%I64u, attempt=%d/%d, retcode=%u, error=%d",
                     ticket, attempt, InpMaxTradeRetries, retcode, GetLastError());

      Sleep(InpTradeRetryDelayMs);
   }

   return false;
}

bool ClosePositionWithRetry(const ulong ticket)
{
   for(int attempt = 1; attempt <= MathMax(1, InpMaxTradeRetries); attempt++)
   {
      ResetLastError();
      if(trade.PositionClose(ticket))
         return true;

      const uint retcode = trade.ResultRetcode();
      if(retcode == TRADE_RETCODE_FROZEN)
         break;

      if(InpEnableLogs)
         PrintFormat("Close failed. Ticket=%I64u, attempt=%d/%d, retcode=%u, error=%d",
                     ticket, attempt, InpMaxTradeRetries, retcode, GetLastError());

      Sleep(InpTradeRetryDelayMs);
   }

   return false;
}

void RegisterEntry(const ENUM_SIGNAL signal)
{
   g_lastEntrySignal  = signal;
   g_lastEntryBarTime = iTime(_Symbol, InpTradeTimeframe, 1);
   g_cooldownUntil    = TimeCurrent() + InpCooldownMinutes * 60;
}

double CalculateLot(const double slDistance)
{
   if(InpLotMode == LOT_FIXED)
      return InpFixedLot;

   if(slDistance <= 0.0 || InpRiskPercent <= 0.0)
      return InpFixedLot;

   const double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   const double riskMoney = balance * InpRiskPercent / 100.0;
   const double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   const double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   if(tickSize <= 0.0 || tickValue <= 0.0)
      return InpFixedLot;

   const double lossPerLot = (slDistance / tickSize) * tickValue;
   if(lossPerLot <= 0.0)
      return InpFixedLot;

   return riskMoney / lossPerLot;
}

double NormalizeLot(const double lot)
{
   const double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0.0)
      return 0.0;

   double normalized = MathFloor(lot / step) * step;
   normalized = MathMax(minLot, MathMin(maxLot, normalized));

   const int digits = (int)MathMax(0, MathRound(-MathLog10(step)));
   return NormalizeDouble(normalized, digits);
}

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}
//+------------------------------------------------------------------+
