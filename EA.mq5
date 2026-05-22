#property strict
#property version   "1.04"
#property description "Professional lightweight XAUUSD M5 EMA 5/13 cross scalper with ATR, EMA distance and slope filters + smart reentry."

#include <Trade/Trade.mqh>

CTrade trade;

// ======================== LICENSE SYSTEM ========================
const long AllowedAccounts[] =
{
   12345678,
   87654321,
   11223344
};

const datetime ExpiryDate = D'2026.12.31 23:59';
const string SUPPORT_WHATSAPP = "0149075857";
const string EA_NAME = "EAPro V1.04";

bool licenseValid = false;
bool licenseExpired = false;

// ======================== PRIMARY INPUTS ========================
input double InpLotSize            = 0.01;       // Lot Size
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_CURRENT; // Timeframe
input bool   InpUseMtfTrendConfirm = false;      // MTF Trend Confirmation ON/OFF
input ENUM_TIMEFRAMES InpMtfTrendTimeframe = PERIOD_H1; // MTF Trend Timeframe
input int    InpEmaFastPeriod      = 5;          // EMA Fast Period
input int    InpEmaSlowPeriod      = 13;         // EMA Slow Period
input int    InpAtrPeriod          = 14;         // ATR Period
input double InpMinimumAtrValue        = 100.0;      // Minimum ATR Value, points
input double InpMinimumEmaDistance     = 30.0;       // Minimum EMA Distance, points
input double InpMinimumEmaSlopePoints  = 30.0;       // Minimum EMA Slope, points
input ulong  InpMagicNumber            = 51313;      // Magic Number
input int    InpSlippage               = 30;         // Slippage, points
input bool   InpUseStopLoss            = false;      // Stop Loss optional ON/OFF
input double InpStopLossPoints     = 500.0;      // Stop Loss, points
input bool   InpUseAtrStopLoss     = false;      // ATR Stop Loss ON/OFF
input double InpAtrStopLossMultiplier = 2.0;     // ATR Stop Loss Multiplier
input bool   InpUseTakeProfit      = false;      // Take Profit optional ON/OFF
input double InpTakeProfitPoints   = 500.0;      // Take Profit, points
input bool   InpUseAtrTakeProfit   = false;      // ATR Take Profit ON/OFF
input double InpAtrTakeProfitMultiplier = 2.0;   // ATR Take Profit Multiplier
input bool   InpUseAtrTrailingStop = false;      // ATR Trailing Stop ON/OFF
input double InpAtrTrailingMultiplier = 1.50;    // ATR Trailing Stop Multiplier
input double InpMaxSpreadPoints       = 50.0;    // Maximum spread to allow entry, points
input bool   InpUseSessionFilter      = false;   // Session filter ON/OFF
input int    InpSessionStartHour      = 7;       // Session start hour (server time)
input int    InpSessionEndHour        = 22;      // Session end hour (server time)
input bool   InpUseBreakeven          = false;   // Breakeven protection ON/OFF
input double InpBreakevenTriggerPoints = 300.0;  // Breakeven trigger, points
input double InpBreakevenOffsetPoints  = 10.0;   // Breakeven offset, points
input bool   InpDebugMode          = false;      // Debug logging ON/OFF

// ======================== REENTRY SYSTEM INPUTS ========================
input bool   InpUseReentry                  = true;     // Reentry System ON/OFF
input int    InpReentryCooldownBars        = 1;         // Cooldown bars between reentries
input int    InpMaxReentriesPerTrend       = 2;         // Max reentries per trend direction
input bool   InpUseSlopeWeakeningBlock     = true;      // Block reentry on slope weakening
input double InpSlopeWeakeningFactor       = 0.80;      // Slope weakening threshold (0-1)
input bool   InpUseDistanceShrinkBlock     = true;      // Block reentry on distance shrinking
input double InpDistanceShrinkFactor       = 0.85;      // Distance shrinking threshold (0-1)

int fastEmaHandle    = INVALID_HANDLE;
int slowEmaHandle    = INVALID_HANDLE;
int atrHandle        = INVALID_HANDLE;
int mtfFastEmaHandle = INVALID_HANDLE;
int mtfSlowEmaHandle = INVALID_HANDLE;

datetime lastBarTime      = 0;
datetime lastTradeBarTime = 0;
datetime lastErrorLogTime = 0;
datetime lastReentryBarTime = 0;

ENUM_TIMEFRAMES activeTimeframe   = PERIOD_CURRENT;
ENUM_TIMEFRAMES mtfTrendTimeframe = PERIOD_H1;

double cachedAtrValue   = 0.0;
datetime cachedAtrBarTime = 0;

double fastBuffer[];
double slowBuffer[];
double atrBuffer[];
double mtfFastBuffer[];
double mtfSlowBuffer[];
double trailingAtrBuffer[];
double extendedFastBuffer[];
double extendedSlowBuffer[];

// ======================== REENTRY STATE TRACKING ========================
int buyReentryCount   = 0;
int sellReentryCount  = 0;
bool previousTrendWasBuy  = false;
bool previousTrendWasSell = false;

enum ENUM_CROSS_SIGNAL
{
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1,
   SIGNAL_SELL = -1
};

struct ManagedPositionStats
{
   int buyCount;
   int sellCount;
   int totalCount;
};

// ======================== LICENSE VALIDATION FUNCTIONS ========================

bool IsAccountAuthorized()
{
   const long accountLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   const int arraySize = ArraySize(AllowedAccounts);

   for(int i = 0; i < arraySize; ++i)
   {
      if(AllowedAccounts[i] == accountLogin)
         return true;
   }

   return false;
}

bool IsExpired()
{
   return (TimeCurrent() > ExpiryDate);
}

int RemainingDays()
{
   const datetime now = TimeCurrent();

   if(now >= ExpiryDate)
      return 0;

   const long secondsDiff = (long)(ExpiryDate - now);
   const int days = (int)(secondsDiff / 86400);

   return (days >= 0) ? days : 0;
}

void DisplayLicenseStatus()
{
   const long accountLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   const int remainingDays = RemainingDays();

   string statusText = EA_NAME + "\n";
   statusText += "License Status : VALID\n";
   statusText += StringFormat("Account ID     : %I64d\n", accountLogin);
   statusText += StringFormat("Expiry Date    : %s\n", TimeToString(ExpiryDate, TIME_DATE));
   statusText += StringFormat("Days Remaining : %d days\n", remainingDays);
   statusText += "\nSupport:\n";
   statusText += "WhatsApp Cikgu Salleh\n";
   statusText += SUPPORT_WHATSAPP + "\n";
   statusText += "----------";

   Comment(statusText);
}

void DisplayInvalidLicense()
{
   string statusText = EA_NAME + "\n";
   statusText += "LICENSE INVALID\n\n";
   statusText += "WhatsApp Cikgu Salleh\n";
   statusText += SUPPORT_WHATSAPP + "\n";
   statusText += "----------";

   Comment(statusText);
}

void DisplayExpiredLicense()
{
   string statusText = EA_NAME + "\n";
   statusText += "LICENSE EXPIRED\n\n";
   statusText += "WhatsApp Cikgu Salleh\n";
   statusText += SUPPORT_WHATSAPP + "\n";
   statusText += "----------";

   Comment(statusText);
}

void DebugLog(const string message)
{
   if(InpDebugMode)
      Print(message);
}

void LogThrottled(const string message, const int throttleSeconds = 30)
{
   const datetime now = TimeCurrent();

   if((now - lastErrorLogTime) >= throttleSeconds)
   {
      Print(message);
      lastErrorLogTime = now;
   }
}

double NormalizePrice(const double price)
{
   return NormalizeDouble(price, _Digits);
}

bool IsValidPositiveNumber(const double value)
{
   return (MathIsValidNumber(value) && value > 0.0);
}

bool IsValidAtrValue(const double atrValue)
{
   return IsValidPositiveNumber(atrValue);
}

double PriceEpsilon()
{
   if(_Point <= 0.0)
      return DBL_EPSILON;

   return MathMax(_Point * 0.10, DBL_EPSILON);
}

double StopModifyEpsilon()
{
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(tickSize <= 0.0)
      tickSize = _Point;

   return MathMax(_Point, tickSize);
}

double PriceToPoints(const double priceValue)
{
   if(_Point <= 0.0 || !MathIsValidNumber(priceValue))
      return 0.0;

   return priceValue / _Point;
}

bool IsTradingSessionAllowed()
{
   if(!InpUseSessionFilter)
      return true;

   if(InpSessionStartHour == InpSessionEndHour)
      return true;

   MqlDateTime dt;
   if(!TimeToStruct(TimeCurrent(), dt))
      return true;

   const int currentHour = dt.hour;

   if(InpSessionStartHour < InpSessionEndHour)
      return (currentHour >= InpSessionStartHour && currentHour < InpSessionEndHour);

   return (currentHour >= InpSessionStartHour || currentHour < InpSessionEndHour);
}

bool IsSpreadAllowed(const MqlTick &tick)
{
   if(InpMaxSpreadPoints <= 0.0 || _Point <= 0.0)
      return true;

   if(!MathIsValidNumber(tick.ask) || !MathIsValidNumber(tick.bid) || tick.ask <= tick.bid)
      return false;

   return (PriceToPoints(tick.ask - tick.bid) <= InpMaxSpreadPoints);
}

bool IsEntryAllowed(const MqlTick &tick)
{
   return IsTradingSessionAllowed() && IsSpreadAllowed(tick);
}

int VolumeDigitsFromStep(const double step)
{
   if(step <= 0.0)
      return 2;

   int digits = 0;
   double value = step;

   while(digits < 8 && MathAbs(value - MathRound(value)) > 0.00000001)
   {
      value *= 10.0;
      ++digits;
   }

   return digits;
}

double NormalizeVolume(const double volume)
{
   const double minVolume  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   const double maxVolume  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   const double volumeStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(volumeStep <= 0.0)
      return volume;

   double normalized = MathMax(minVolume, MathMin(maxVolume, volume));
   normalized = minVolume + MathRound((normalized - minVolume) / volumeStep) * volumeStep;

   return NormalizeDouble(MathMax(minVolume, MathMin(maxVolume, normalized)), VolumeDigitsFromStep(volumeStep));
}

bool IsTransientTradeRetcode(const uint retcode)
{
   return (retcode == TRADE_RETCODE_REQUOTE ||
           retcode == TRADE_RETCODE_PRICE_CHANGED ||
           retcode == TRADE_RETCODE_PRICE_OFF ||
           retcode == TRADE_RETCODE_TIMEOUT ||
           retcode == TRADE_RETCODE_CONNECTION ||
           retcode == TRADE_RETCODE_TOO_MANY_REQUESTS ||
           retcode == TRADE_RETCODE_LOCKED);
}

bool AreIndicatorsReady()
{
   if(BarsCalculated(fastEmaHandle) < 4 ||
      BarsCalculated(slowEmaHandle) < 4 ||
      BarsCalculated(atrHandle) < 2)
      return false;

   if(InpUseMtfTrendConfirm &&
      (BarsCalculated(mtfFastEmaHandle) < 2 || BarsCalculated(mtfSlowEmaHandle) < 2))
      return false;

   return true;
}

bool IsNewBar()
{
   long seriesTime = 0;

   if(!SeriesInfoInteger(_Symbol, activeTimeframe, SERIES_LASTBAR_DATE, seriesTime))
      return false;

   const datetime currentBarTime = (datetime)seriesTime;

   if(currentBarTime <= 0 || currentBarTime == lastBarTime)
      return false;

   lastBarTime = currentBarTime;
   return true;
}

bool LoadClosedCandleData(double &fast1,
                          double &fast2,
                          double &slow1,
                          double &slow2,
                          double &atr1)
{
   if(!AreIndicatorsReady())
      return false;

   if(CopyBuffer(fastEmaHandle, 0, 1, 2, fastBuffer) != 2)
   {
      LogThrottled(StringFormat("Failed to copy fast EMA buffer. Error: %d", GetLastError()));
      return false;
   }

   if(CopyBuffer(slowEmaHandle, 0, 1, 2, slowBuffer) != 2)
   {
      LogThrottled(StringFormat("Failed to copy slow EMA buffer. Error: %d", GetLastError()));
      return false;
   }

   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuffer) != 1)
   {
      LogThrottled(StringFormat("Failed to copy ATR buffer. Error: %d", GetLastError()));
      return false;
   }

   if(!IsValidAtrValue(atrBuffer[0]))
      return false;

   fast1 = fastBuffer[0];
   fast2 = fastBuffer[1];
   slow1 = slowBuffer[0];
   slow2 = slowBuffer[1];
   atr1  = atrBuffer[0];

   cachedAtrValue   = atr1;
   cachedAtrBarTime = iTime(_Symbol, activeTimeframe, 1);

   return true;
}

bool LoadExtendedCandleData(double &fast1,
                            double &fast2,
                            double &fast3,
                            double &slow1,
                            double &slow2,
                            double &slow3,
                            double &atr1)
{
   if(BarsCalculated(fastEmaHandle) < 4 ||
      BarsCalculated(slowEmaHandle) < 4 ||
      BarsCalculated(atrHandle) < 2)
      return false;

   if(CopyBuffer(fastEmaHandle, 0, 1, 3, extendedFastBuffer) != 3)
      return false;

   if(CopyBuffer(slowEmaHandle, 0, 1, 3, extendedSlowBuffer) != 3)
      return false;

   if(CopyBuffer(atrHandle, 0, 1, 1, atrBuffer) != 1)
      return false;

   if(!IsValidAtrValue(atrBuffer[0]))
      return false;

   fast1 = extendedFastBuffer[0];
   fast2 = extendedFastBuffer[1];
   fast3 = extendedFastBuffer[2];
   slow1 = extendedSlowBuffer[0];
   slow2 = extendedSlowBuffer[1];
   slow3 = extendedSlowBuffer[2];
   atr1  = atrBuffer[0];

   return true;
}

ENUM_CROSS_SIGNAL GetCrossSignal(const double fast1,
                                 const double fast2,
                                 const double slow1,
                                 const double slow2)
{
   const double eps = PriceEpsilon();

   if(fast2 <= slow2 + eps && fast1 > slow1 + eps)
      return SIGNAL_BUY;

   if(fast2 >= slow2 - eps && fast1 < slow1 - eps)
      return SIGNAL_SELL;

   return SIGNAL_NONE;
}

bool PassesFilters(const ENUM_CROSS_SIGNAL signal,
                   const double fast1,
                   const double fast2,
                   const double slow1,
                   const double atr1)
{
   if(signal == SIGNAL_NONE || _Point <= 0.0 || !IsValidAtrValue(atr1))
      return false;

   const double atrPoints          = PriceToPoints(atr1);
   const double emaDistancePoints  = PriceToPoints(MathAbs(fast1 - slow1));
   const double slopePoints        = PriceToPoints(MathAbs(fast1 - fast2));
   const double minimumSlopePoints = InpMinimumEmaSlopePoints;

   if(atrPoints + DBL_EPSILON < InpMinimumAtrValue)
      return false;

   if(emaDistancePoints + DBL_EPSILON < InpMinimumEmaDistance)
      return false;

   if(slopePoints + DBL_EPSILON < minimumSlopePoints)
      return false;

   return true;
}

bool PassesMtfTrendConfirm(const ENUM_CROSS_SIGNAL signal)
{
   if(!InpUseMtfTrendConfirm || signal == SIGNAL_NONE)
      return true;

   if(BarsCalculated(mtfFastEmaHandle) < 2 || BarsCalculated(mtfSlowEmaHandle) < 2)
      return false;

   if(CopyBuffer(mtfFastEmaHandle, 0, 1, 1, mtfFastBuffer) != 1)
   {
      LogThrottled(StringFormat("Failed to copy MTF fast EMA buffer. Error: %d", GetLastError()));
      return false;
   }

   if(CopyBuffer(mtfSlowEmaHandle, 0, 1, 1, mtfSlowBuffer) != 1)
   {
      LogThrottled(StringFormat("Failed to copy MTF slow EMA buffer. Error: %d", GetLastError()));
      return false;
   }

   if(signal == SIGNAL_BUY)
      return (mtfFastBuffer[0] > mtfSlowBuffer[0]);

   if(signal == SIGNAL_SELL)
      return (mtfFastBuffer[0] < mtfSlowBuffer[0]);

   return false;
}

bool IsManagedPositionSelectedByIndex(const int index)
{
   const ulong ticket = PositionGetTicket(index);

   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;

   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;

   if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
      return false;

   return true;
}

ManagedPositionStats GetManagedPositionStats()
{
   ManagedPositionStats stats;
   stats.buyCount   = 0;
   stats.sellCount  = 0;
   stats.totalCount = 0;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(!IsManagedPositionSelectedByIndex(i))
         continue;

      const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if(type == POSITION_TYPE_BUY)
         ++stats.buyCount;
      else if(type == POSITION_TYPE_SELL)
         ++stats.sellCount;

      ++stats.totalCount;
   }

   return stats;
}

double RequiredStopDistance()
{
   const int stopsLevel  = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   const int freezeLevel = (int)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);

   return MathMax(stopsLevel, freezeLevel) * _Point;
}

bool IsStopDistanceValidForPosition(const ENUM_POSITION_TYPE type,
                                    const double stopPrice,
                                    const MqlTick &tick)
{
   if(stopPrice <= 0.0)
      return true;

   if(!MathIsValidNumber(stopPrice))
      return false;

   const double requiredDistance = RequiredStopDistance();

   if(requiredDistance <= 0.0)
      return true;

   if(type == POSITION_TYPE_BUY)
      return ((tick.bid - stopPrice) + DBL_EPSILON >= requiredDistance);

   if(type == POSITION_TYPE_SELL)
      return ((stopPrice - tick.ask) + DBL_EPSILON >= requiredDistance);

   return false;
}

void CalculateInitialStops(const ENUM_CROSS_SIGNAL signal,
                           const MqlTick &tick,
                           double &sl,
                           double &tp)
{
   sl = 0.0;
   tp = 0.0;

   if(signal == SIGNAL_BUY)
   {
      if(InpUseStopLoss)
         sl = NormalizePrice(tick.ask - InpStopLossPoints * _Point);
      else if(InpUseAtrStopLoss && IsValidAtrValue(cachedAtrValue))
         sl = NormalizePrice(tick.ask - cachedAtrValue * InpAtrStopLossMultiplier);

      if(InpUseTakeProfit)
         tp = NormalizePrice(tick.ask + InpTakeProfitPoints * _Point);
      else if(InpUseAtrTakeProfit && IsValidAtrValue(cachedAtrValue))
         tp = NormalizePrice(tick.ask + cachedAtrValue * InpAtrTakeProfitMultiplier);
   }
   else if(signal == SIGNAL_SELL)
   {
      if(InpUseStopLoss)
         sl = NormalizePrice(tick.bid + InpStopLossPoints * _Point);
      else if(InpUseAtrStopLoss && IsValidAtrValue(cachedAtrValue))
         sl = NormalizePrice(tick.bid + cachedAtrValue * InpAtrStopLossMultiplier);

      if(InpUseTakeProfit)
         tp = NormalizePrice(tick.bid - InpTakeProfitPoints * _Point);
      else if(InpUseAtrTakeProfit && IsValidAtrValue(cachedAtrValue))
         tp = NormalizePrice(tick.bid - cachedAtrValue * InpAtrTakeProfitMultiplier);
   }

   if(!MathIsValidNumber(sl))
      sl = 0.0;

   if(!MathIsValidNumber(tp))
      tp = 0.0;
}

bool ExecuteBuyWithRetry(const double volume, const double sl, const double tp)
{
   for(int attempt = 0; attempt < 2; ++attempt)
   {
      if(trade.Buy(volume, _Symbol, 0.0, sl, tp, "EMA cross buy"))
         return true;

      const uint retcode = trade.ResultRetcode();
      if(!IsTransientTradeRetcode(retcode))
         break;
   }

   LogThrottled(StringFormat("BUY failed. Retcode: %u, Description: %s",
                             trade.ResultRetcode(),
                             trade.ResultRetcodeDescription()));
   return false;
}

bool ExecuteSellWithRetry(const double volume, const double sl, const double tp)
{
   for(int attempt = 0; attempt < 2; ++attempt)
   {
      if(trade.Sell(volume, _Symbol, 0.0, sl, tp, "EMA cross sell"))
         return true;

      const uint retcode = trade.ResultRetcode();
      if(!IsTransientTradeRetcode(retcode))
         break;
   }

   LogThrottled(StringFormat("SELL failed. Retcode: %u, Description: %s",
                             trade.ResultRetcode(),
                             trade.ResultRetcodeDescription()));
   return false;
}

bool OpenSignalPosition(const ENUM_CROSS_SIGNAL signal, const MqlTick &tick)
{
   if(signal == SIGNAL_NONE)
      return false;

   if(lastTradeBarTime == lastBarTime)
   {
      const ManagedPositionStats currentStats = GetManagedPositionStats();
      if(currentStats.totalCount > 0)
         return false;
   }

   if(!IsEntryAllowed(tick))
      return false;

   const double volume = NormalizeVolume(InpLotSize);

   double sl = 0.0;
   double tp = 0.0;

   CalculateInitialStops(signal, tick, sl, tp);

   bool result = false;

   if(signal == SIGNAL_BUY)
   {
      if(!IsStopDistanceValidForPosition(POSITION_TYPE_BUY, sl, tick))
         sl = 0.0;

      result = ExecuteBuyWithRetry(volume, sl, tp);
   }
   else if(signal == SIGNAL_SELL)
   {
      if(!IsStopDistanceValidForPosition(POSITION_TYPE_SELL, sl, tick))
         sl = 0.0;

      result = ExecuteSellWithRetry(volume, sl, tp);
   }

   if(result)
      lastTradeBarTime = lastBarTime;

   return result;
}

bool ClosePositionByTicket(const ulong ticket)
{
   for(int attempt = 0; attempt < 2; ++attempt)
   {
      if(!PositionSelectByTicket(ticket))
         return false;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         return false;

      if(trade.PositionClose(ticket, InpSlippage))
         return true;

      const uint retcode = trade.ResultRetcode();
      if(!IsTransientTradeRetcode(retcode))
         break;
   }

   LogThrottled(StringFormat("Position close failed. Ticket: %I64u, Retcode: %u, Description: %s",
                             ticket,
                             trade.ResultRetcode(),
                             trade.ResultRetcodeDescription()));
   return false;
}

int CloseOppositePositions(const ENUM_CROSS_SIGNAL signal)
{
   int closedCount = 0;

   if(signal == SIGNAL_NONE)
      return closedCount;

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(!IsManagedPositionSelectedByIndex(i))
         continue;

      const ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

      if((signal == SIGNAL_BUY && type == POSITION_TYPE_SELL) ||
         (signal == SIGNAL_SELL && type == POSITION_TYPE_BUY))
      {
         if(ClosePositionByTicket(ticket))
            ++closedCount;
      }
   }

   return closedCount;
}

bool GetClosedAtrForTrailing(double &atrValue)
{
   const datetime closedBarTime = iTime(_Symbol, activeTimeframe, 1);

   if(closedBarTime <= 0)
      return false;

   if(cachedAtrBarTime == closedBarTime && IsValidAtrValue(cachedAtrValue))
   {
      atrValue = cachedAtrValue;
      return true;
   }

   if(CopyBuffer(atrHandle, 0, 1, 1, trailingAtrBuffer) != 1)
   {
      LogThrottled(StringFormat("Failed to copy trailing ATR buffer. Error: %d", GetLastError()));
      return false;
   }

   if(!IsValidAtrValue(trailingAtrBuffer[0]))
      return false;

   cachedAtrValue   = trailingAtrBuffer[0];
   cachedAtrBarTime = closedBarTime;
   atrValue         = cachedAtrValue;

   return true;
}

bool ModifyPositionWithRetry(const ulong ticket, const double sl, const double tp)
{
   for(int attempt = 0; attempt < 2; ++attempt)
   {
      if(!PositionSelectByTicket(ticket))
         return false;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
         return false;

      if(trade.PositionModify(ticket, sl, tp))
         return true;

      const uint retcode = trade.ResultRetcode();
      if(!IsTransientTradeRetcode(retcode))
         break;
   }

   LogThrottled(StringFormat("Position modify failed. Ticket: %I64u, Retcode: %u, Description: %s",
                             ticket,
                             trade.ResultRetcode(),
                             trade.ResultRetcodeDescription()));
   return false;
}

void ManageAtrTrailingStop(const MqlTick &tick)
{
   if(!InpUseAtrTrailingStop)
      return;

   double atrValue = 0.0;

   if(!GetClosedAtrForTrailing(atrValue))
      return;

   const double trailingDistance = atrValue * InpAtrTrailingMultiplier;

   if(!IsValidPositiveNumber(trailingDistance))
      return;

   const double modifyEpsilon = MathMax(StopModifyEpsilon() * 1.5, _Point * 2.0);

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(!IsManagedPositionSelectedByIndex(i))
         continue;

      const ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      const double currentSl = PositionGetDouble(POSITION_SL);
      const double currentTp = PositionGetDouble(POSITION_TP);

      double newSl = 0.0;

      if(type == POSITION_TYPE_BUY)
      {
         newSl = NormalizePrice(tick.bid - trailingDistance);

         if(newSl <= 0.0)
            continue;

         if(currentSl > 0.0 && newSl <= currentSl + modifyEpsilon)
            continue;

         if(!IsStopDistanceValidForPosition(POSITION_TYPE_BUY, newSl, tick))
            continue;
      }
      else if(type == POSITION_TYPE_SELL)
      {
         newSl = NormalizePrice(tick.ask + trailingDistance);

         if(newSl <= 0.0)
            continue;

         if(currentSl > 0.0 && newSl >= currentSl - modifyEpsilon)
            continue;

         if(!IsStopDistanceValidForPosition(POSITION_TYPE_SELL, newSl, tick))
            continue;
      }
      else
      {
         continue;
      }

      ModifyPositionWithRetry(ticket, newSl, currentTp);
   }
}

void ManageBreakeven(const MqlTick &tick)
{
   if(!InpUseBreakeven || _Point <= 0.0)
      return;

   const double triggerDistance = InpBreakevenTriggerPoints * _Point;
   const double offsetDistance = InpBreakevenOffsetPoints * _Point;
   const double modifyEpsilon = MathMax(StopModifyEpsilon() * 1.5, _Point * 2.0);

   for(int i = PositionsTotal() - 1; i >= 0; --i)
   {
      if(!IsManagedPositionSelectedByIndex(i))
         continue;

      const ulong ticket = (ulong)PositionGetInteger(POSITION_TICKET);
      const ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      const double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      const double currentSl = PositionGetDouble(POSITION_SL);
      const double currentTp = PositionGetDouble(POSITION_TP);
      double targetSl = 0.0;

      if(!MathIsValidNumber(openPrice) || openPrice <= 0.0)
         continue;

      if(type == POSITION_TYPE_BUY)
      {
         const double profit = tick.bid - openPrice;
         if(profit < triggerDistance)
            continue;

         targetSl = NormalizePrice(openPrice + offsetDistance);
         if(targetSl <= 0.0)
            continue;

         if(currentSl > 0.0 && targetSl <= currentSl + modifyEpsilon)
            continue;

         if(!IsStopDistanceValidForPosition(POSITION_TYPE_BUY, targetSl, tick))
            continue;
      }
      else if(type == POSITION_TYPE_SELL)
      {
         const double profit = openPrice - tick.ask;
         if(profit < triggerDistance)
            continue;

         targetSl = NormalizePrice(openPrice - offsetDistance);
         if(targetSl <= 0.0)
            continue;

         if(currentSl > 0.0 && targetSl >= currentSl - modifyEpsilon)
            continue;

         if(!IsStopDistanceValidForPosition(POSITION_TYPE_SELL, targetSl, tick))
            continue;
      }
      else
      {
         continue;
      }

      ModifyPositionWithRetry(ticket, targetSl, currentTp);
   }
}

// ======================== REENTRY SYSTEM FUNCTIONS ========================

bool IsExhaustionDetected(const double fast1,
                          double fast2,
                          const double fast3,
                          const double slow1,
                          const double slow2,
                          const double slow3)
{
   if(!InpUseSlopeWeakeningBlock && !InpUseDistanceShrinkBlock)
      return false;

   const double eps = PriceEpsilon();
   const double minimumSlopeMovement = MathMax(eps * 10.0, _Point * 2.0);
   const double minimumDistanceMovement = MathMax(eps * 10.0, _Point * 3.0);

   bool slopeWeakening = false;
   bool distanceShrinking = false;

   // A. EMA Slope Weakening Detection
   if(InpUseSlopeWeakeningBlock)
   {
      const double currentSlope = MathAbs(fast1 - fast2);
      const double previousSlope = MathAbs(fast2 - fast3);

      if(previousSlope > minimumSlopeMovement && currentSlope < previousSlope * InpSlopeWeakeningFactor)
      {
         slopeWeakening = true;
         DebugLog(StringFormat("Exhaustion: Slope weakening detected. Current=%.5f Previous=%.5f",
                              currentSlope, previousSlope));
      }
   }

   // B. EMA Distance Shrinking Detection
   if(InpUseDistanceShrinkBlock)
   {
      const double currentDistance = MathAbs(fast1 - slow1);
      const double previousDistance = MathAbs(fast2 - slow2);

      if(previousDistance > minimumDistanceMovement && currentDistance < previousDistance * InpDistanceShrinkFactor)
      {
         distanceShrinking = true;
         DebugLog(StringFormat("Exhaustion: Distance shrinking detected. Current=%.5f Previous=%.5f",
                              currentDistance, previousDistance));
      }
   }

   return (slopeWeakening || distanceShrinking);
}

bool CanReentryBePlaced(const ENUM_CROSS_SIGNAL signal,
                        const double fast1,
                        const double fast2,
                        const double fast3,
                        const double slow1,
                        const double slow2,
                        const double slow3,
                        const double atr1,
                        const ManagedPositionStats &stats)
{
   // 1. Reentry disabled
   if(!InpUseReentry)
      return false;

   // 2. No open positions
   if(stats.totalCount > 0)
      return false;

   // 3. Must be same-direction signal
   if(signal == SIGNAL_NONE)
      return false;

   // 4. Same-bar prevention
   if(lastReentryBarTime == lastBarTime)
      return false;

   // 5. Reentry count limits
   if(signal == SIGNAL_BUY && buyReentryCount >= InpMaxReentriesPerTrend)
      return false;

   if(signal == SIGNAL_SELL && sellReentryCount >= InpMaxReentriesPerTrend)
      return false;

   // 6. Cooldown between reentries
   if(signal == SIGNAL_BUY && !previousTrendWasBuy)
   {
      buyReentryCount = 0;
   }
   else if(signal == SIGNAL_SELL && !previousTrendWasSell)
   {
      sellReentryCount = 0;
   }

   if(InpReentryCooldownBars > 0)
   {
      const int periodSeconds = PeriodSeconds(activeTimeframe);
      if(periodSeconds <= 0)
         return false;

      const long deltaSeconds = (long)(lastBarTime - lastReentryBarTime);
      if(deltaSeconds < 0)
         return false;

      const int barsSinceLastReentry = (int)(deltaSeconds / periodSeconds);
      if(barsSinceLastReentry < InpReentryCooldownBars)
         return false;
   }

   // 7. Exhaustion detection (blocks reentry)
   if(IsExhaustionDetected(fast1, fast2, fast3, slow1, slow2, slow3))
      return false;

   // 8. Filters must pass
   if(!PassesFilters(signal, fast1, fast2, slow1, atr1))
      return false;

   // 9. MTF confirmation (if enabled)
   if(!PassesMtfTrendConfirm(signal))
      return false;

   return true;
}

void ProcessReentry(const ENUM_CROSS_SIGNAL signal, const MqlTick &tick)
{
   if(signal == SIGNAL_BUY)
   {
      if(OpenSignalPosition(signal, tick))
      {
         ++buyReentryCount;
         lastReentryBarTime = lastBarTime;
         previousTrendWasBuy = true;
         previousTrendWasSell = false;
         DebugLog(StringFormat("BUY reentry #%d placed.", buyReentryCount));
      }
   }
   else if(signal == SIGNAL_SELL)
   {
      if(OpenSignalPosition(signal, tick))
      {
         ++sellReentryCount;
         lastReentryBarTime = lastBarTime;
         previousTrendWasSell = true;
         previousTrendWasBuy = false;
         DebugLog(StringFormat("SELL reentry #%d placed.", sellReentryCount));
      }
   }
}

void ResetReentryCountersOnCrossOver(const ENUM_CROSS_SIGNAL signal)
{
   if(signal == SIGNAL_BUY)
   {
      if(previousTrendWasSell)
      {
         buyReentryCount = 0;
         sellReentryCount = 0;
         previousTrendWasBuy = true;
         previousTrendWasSell = false;
         DebugLog("Reentry counters reset: BUY trend started.");
      }
   }
   else if(signal == SIGNAL_SELL)
   {
      if(previousTrendWasBuy)
      {
         buyReentryCount = 0;
         sellReentryCount = 0;
         previousTrendWasSell = true;
         previousTrendWasBuy = false;
         DebugLog("Reentry counters reset: SELL trend started.");
      }
   }
}

bool InitializeBuffers()
{
   if(ArrayResize(fastBuffer, 2) != 2)
      return false;

   if(ArrayResize(slowBuffer, 2) != 2)
      return false;

   if(ArrayResize(atrBuffer, 1) != 1)
      return false;

   if(ArrayResize(mtfFastBuffer, 1) != 1)
      return false;

   if(ArrayResize(mtfSlowBuffer, 1) != 1)
      return false;

   if(ArrayResize(trailingAtrBuffer, 1) != 1)
      return false;

   if(ArrayResize(extendedFastBuffer, 3) != 3)
      return false;

   if(ArrayResize(extendedSlowBuffer, 3) != 3)
      return false;

   ArraySetAsSeries(fastBuffer, true);
   ArraySetAsSeries(slowBuffer, true);
   ArraySetAsSeries(atrBuffer, true);
   ArraySetAsSeries(mtfFastBuffer, true);
   ArraySetAsSeries(mtfSlowBuffer, true);
   ArraySetAsSeries(trailingAtrBuffer, true);
   ArraySetAsSeries(extendedFastBuffer, true);
   ArraySetAsSeries(extendedSlowBuffer, true);

   return true;
}

int OnInit()
{
   activeTimeframe   = (InpTimeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpTimeframe;
   mtfTrendTimeframe = (InpMtfTrendTimeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)_Period : InpMtfTrendTimeframe;

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpSlippage);
   trade.SetTypeFillingBySymbol(_Symbol);

   if(!InitializeBuffers())
   {
      Print("Failed to initialize indicator buffers.");
      return INIT_FAILED;
   }

   fastEmaHandle = iMA(_Symbol, activeTimeframe, InpEmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
   slowEmaHandle = iMA(_Symbol, activeTimeframe, InpEmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle     = iATR(_Symbol, activeTimeframe, InpAtrPeriod);

   if(fastEmaHandle == INVALID_HANDLE ||
      slowEmaHandle == INVALID_HANDLE ||
      atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create primary indicator handles.");
      return INIT_FAILED;
   }

   if(InpUseMtfTrendConfirm)
   {
      mtfFastEmaHandle = iMA(_Symbol, mtfTrendTimeframe, InpEmaFastPeriod, 0, MODE_EMA, PRICE_CLOSE);
      mtfSlowEmaHandle = iMA(_Symbol, mtfTrendTimeframe, InpEmaSlowPeriod, 0, MODE_EMA, PRICE_CLOSE);

      if(mtfFastEmaHandle == INVALID_HANDLE || mtfSlowEmaHandle == INVALID_HANDLE)
      {
         Print("Failed to create MTF indicator handles.");
         return INIT_FAILED;
      }
   }

   lastBarTime      = 0;
   lastTradeBarTime = 0;
   lastErrorLogTime = 0;
   lastReentryBarTime = 0;
   cachedAtrValue   = 0.0;
   cachedAtrBarTime = 0;
   buyReentryCount  = 0;
   sellReentryCount = 0;
   previousTrendWasBuy  = false;
   previousTrendWasSell = false;

   AreIndicatorsReady();

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   if(fastEmaHandle != INVALID_HANDLE)
   {
      IndicatorRelease(fastEmaHandle);
      fastEmaHandle = INVALID_HANDLE;
   }

   if(slowEmaHandle != INVALID_HANDLE)
   {
      IndicatorRelease(slowEmaHandle);
      slowEmaHandle = INVALID_HANDLE;
   }

   if(atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(atrHandle);
      atrHandle = INVALID_HANDLE;
   }

   if(mtfFastEmaHandle != INVALID_HANDLE)
   {
      IndicatorRelease(mtfFastEmaHandle);
      mtfFastEmaHandle = INVALID_HANDLE;
   }

   if(mtfSlowEmaHandle != INVALID_HANDLE)
   {
      IndicatorRelease(mtfSlowEmaHandle);
      mtfSlowEmaHandle = INVALID_HANDLE;
   }
}

void OnTick()
{
   // ======================== LICENSE VALIDATION ========================
   if(!IsAccountAuthorized())
   {
      DisplayInvalidLicense();
      return;
   }

   if(IsExpired())
   {
      DisplayExpiredLicense();
      return;
   }

   // ======================== DISPLAY LICENSE STATUS ========================
   DisplayLicenseStatus();

   // ======================== TRADING LOGIC (ORIGINAL) ========================
   MqlTick tick;

   if(!SymbolInfoTick(_Symbol, tick))
      return;

   if(!AreIndicatorsReady())
      return;

   const bool newBar = IsNewBar();

   if(newBar)
   {
      double fast1 = 0.0;
      double fast2 = 0.0;
      double slow1 = 0.0;
      double slow2 = 0.0;
      double atr1  = 0.0;

      if(LoadClosedCandleData(fast1, fast2, slow1, slow2, atr1))
      {
         const ENUM_CROSS_SIGNAL signal = GetCrossSignal(fast1, fast2, slow1, slow2);
         ManagedPositionStats stats = GetManagedPositionStats();

         // PRIMARY SIGNAL LOGIC
         if(signal != SIGNAL_NONE)
         {
            const int closedCount = CloseOppositePositions(signal);

            if(closedCount > 0)
               stats = GetManagedPositionStats();

            ResetReentryCountersOnCrossOver(signal);

            if(stats.totalCount == 0 &&
               PassesFilters(signal, fast1, fast2, slow1, atr1) &&
               PassesMtfTrendConfirm(signal))
            {
               OpenSignalPosition(signal, tick);

               if(signal == SIGNAL_BUY)
               {
                  buyReentryCount = 0;
                  previousTrendWasBuy = true;
                  previousTrendWasSell = false;
               }
               else if(signal == SIGNAL_SELL)
               {
                  sellReentryCount = 0;
                  previousTrendWasSell = true;
                  previousTrendWasBuy = false;
               }
            }
         }

         // REENTRY LOGIC
         if(InpUseReentry && stats.totalCount == 0)
         {
            double fast3 = 0.0;
            double slow3 = 0.0;

            if(LoadExtendedCandleData(fast1, fast2, fast3, slow1, slow2, slow3, atr1))
            {
               ENUM_CROSS_SIGNAL reentrySignal = SIGNAL_NONE;

               if(previousTrendWasBuy && fast1 > slow1)
               {
                  reentrySignal = SIGNAL_BUY;
               }
               else if(previousTrendWasSell && fast1 < slow1)
               {
                  reentrySignal = SIGNAL_SELL;
               }

               if(CanReentryBePlaced(reentrySignal, fast1, fast2, fast3, slow1, slow2, slow3, atr1, stats))
               {
                  ProcessReentry(reentrySignal, tick);
               }
            }
         }

         ManageAtrTrailingStop(tick);

         if(InpUseBreakeven)
            ManageBreakeven(tick);
      }
   }
}
