//+------------------------------------------------------------------+
//|                                         SwingTrendFollower.mq5   |
//|                        Multi-Timeframe Swing Trend Following EA  |
//|                                                                  |
//| Strategy: Identifies swing highs/lows on two timeframes.         |
//| Higher TF determines trend direction, Signal TF provides entries.|
//| Non-repainting fractal-based swing detection.                    |
//+------------------------------------------------------------------+
#property copyright "SwingTrendFollower EA"
#property link      ""
#property version   "1.00"
#property strict
#property description "Multi-Timeframe Swing Trend Following Expert Advisor"
#property description "Uses fractal-based swing detection on two timeframes"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+
enum ENUM_SL_TYPE
{
   SL_POINTS = 0,    // Points
   SL_PERCENT = 1    // Percent of Price
};

enum ENUM_TP_TYPE
{
   TP_NONE = 0,      // No Take Profit
   TP_POINTS = 1,    // Points
   TP_PERCENT = 2    // Percent of Price
};

enum ENUM_TREND_STATE
{
   TREND_NONE = 0,   // No Trend
   TREND_LONG = 1,   // Uptrend
   TREND_SHORT = 2   // Downtrend
};

enum ENUM_SWING_TYPE
{
   SWING_HIGH = 0,   // Swing High
   SWING_LOW = 1     // Swing Low
};

//+------------------------------------------------------------------+
//| Input Parameters                                                  |
//+------------------------------------------------------------------+
input group "══════════ Timeframe Settings ══════════"
input ENUM_TIMEFRAMES   InpSignalTimeframe       = PERIOD_M15;    // Signal Timeframe
input ENUM_TIMEFRAMES   InpTrendTimeframe        = PERIOD_H1;     // Trend Timeframe (Higher)

input group "══════════ Swing Detection ══════════"
input int               InpSwingDepth            = 5;             // Swing Depth (bars on each side)

input group "══════════ Trend Confirmation ══════════"
input int               InpTrendConfirmCount     = 2;             // HTF Trend Confirmation (x consecutive HH/HL or LH/LL)
input int               InpSignalConfirmCount    = 2;             // Signal Confirmation (y consecutive HH/HL or LH/LL)

input group "══════════ Risk Management ══════════"
input double            InpRiskAmount            = 100.0;         // Risk Amount (account currency)
input ENUM_SL_TYPE      InpSLType                = SL_POINTS;     // Stop Loss Type
input double            InpSLValue               = 500.0;         // Stop Loss Value (points or %)
input bool              InpSLUseSwing            = false;         // Use Last Swing as SL (overrides SL Type)
input double            InpSLSwingBuffer         = 50.0;          // Swing SL Buffer (points beyond swing)

input group "══════════ Take Profit ══════════"
input bool              InpUseTP                 = true;          // Use Take Profit
input ENUM_TP_TYPE      InpTPType                = TP_POINTS;     // Take Profit Type
input double            InpTPValue               = 1000.0;        // Take Profit Value (points or %)

input group "══════════ Trade Settings ══════════"
input int               InpMaxPositionsPerTrend  = 1;             // Max Positions per Trend
input ulong             InpMagicNumber           = 987654;        // Magic Number
input int               InpSlippage              = 30;            // Slippage (points)

input group "══════════ Visualization - Swings ══════════"
input color             InpSignalHighColor       = clrRed;        // Signal TF Swing High Color
input color             InpSignalLowColor        = clrDodgerBlue; // Signal TF Swing Low Color
input color             InpTrendHighColor        = clrMaroon;     // Trend TF Swing High Color
input color             InpTrendLowColor         = clrDarkBlue;   // Trend TF Swing Low Color
input int               InpSignalArrowSize       = 2;             // Signal TF Arrow Size
input int               InpTrendArrowSize        = 3;             // Trend TF Arrow Size

input group "══════════ Visualization - Trend Lines ══════════"
input color             InpUptrendLineColor      = clrLime;       // Uptrend Line Color
input color             InpDowntrendLineColor    = clrOrangeRed;  // Downtrend Line Color
input int               InpTrendLineWidth        = 2;             // Trend Line Width

input group "══════════ Visualization - Rectangles ══════════"
input bool              InpShowRectangles        = true;          // Show Trend Rectangles
input color             InpUptrendRectColor      = clrLightGreen; // Uptrend Rectangle Color
input color             InpDowntrendRectColor    = clrMistyRose;  // Downtrend Rectangle Color

//+------------------------------------------------------------------+
//| Structures                                                        |
//+------------------------------------------------------------------+
struct SwingPoint
{
   datetime          time;           // Time of the swing bar
   double            price;          // Price level of swing
   ENUM_SWING_TYPE   type;           // High or Low
   long              barIdentifier;  // Unique bar identifier to prevent duplicates
   bool              isDrawn;        // Whether visualization has been created

   void Reset()
   {
      time = 0;
      price = 0;
      type = SWING_HIGH;
      barIdentifier = 0;
      isDrawn = false;
   }
};

struct TrendInfo
{
   ENUM_TREND_STATE  state;              // Current trend state
   datetime          startTime;          // When trend started
   double            lastHigh;           // Last confirmed swing high
   double            lastLow;            // Last confirmed swing low
   datetime          lastHighTime;       // Time of last high
   datetime          lastLowTime;        // Time of last low
   int               positionsOpened;    // Positions opened in this trend
   long              trendIdentifier;    // Unique identifier for this trend

   void Reset()
   {
      state = TREND_NONE;
      startTime = 0;
      lastHigh = 0;
      lastLow = 0;
      lastHighTime = 0;
      lastLowTime = 0;
      positionsOpened = 0;
      trendIdentifier = 0;
   }
};

//+------------------------------------------------------------------+
//| Global Variables                                                  |
//+------------------------------------------------------------------+
// Trade objects
CTrade            g_Trade;
CPositionInfo     g_PositionInfo;
CAccountInfo      g_AccountInfo;
CSymbolInfo       g_SymbolInfo;

// Swing point arrays
SwingPoint        g_TrendSwings[];      // Higher timeframe swings
SwingPoint        g_SignalSwings[];     // Signal timeframe swings

// Trend tracking
TrendInfo         g_TrendInfo;          // Higher TF trend info
TrendInfo         g_SignalTrendInfo;    // Signal TF trend info (for entry signals)

// Last processed bar times (to prevent reprocessing)
datetime          g_LastTrendBarTime = 0;
datetime          g_LastSignalBarTime = 0;

// Object naming prefix
string            g_ObjectPrefix = "SWTF_";

// Maximum swings to keep in memory
const int         MAX_SWINGS = 200;

// Entry signal tracking
datetime          g_LastEntrySignalTime = 0;

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   //--- Validate input parameters
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   //--- Initialize symbol info
   if(!g_SymbolInfo.Name(_Symbol))
   {
      Print("ERROR: Failed to initialize symbol info for ", _Symbol);
      return INIT_FAILED;
   }
   g_SymbolInfo.Refresh();
   g_SymbolInfo.RefreshRates();

   //--- Setup trade object
   g_Trade.SetExpertMagicNumber(InpMagicNumber);
   g_Trade.SetDeviationInPoints(InpSlippage);
   g_Trade.SetTypeFilling(GetFillingMode());
   g_Trade.SetAsyncMode(false);

   //--- Initialize arrays
   ArrayResize(g_TrendSwings, 0, MAX_SWINGS);
   ArrayResize(g_SignalSwings, 0, MAX_SWINGS);

   //--- Reset trend info
   g_TrendInfo.Reset();
   g_SignalTrendInfo.Reset();

   //--- Load historical swings
   if(!LoadHistoricalSwings())
   {
      Print("WARNING: Could not load all historical swings");
   }

   //--- Perform initial trend analysis
   AnalyzeHTFTrend();

   //--- Count existing positions for this trend
   g_TrendInfo.positionsOpened = CountEAPositions();

   Print("═══════════════════════════════════════════════════════");
   Print("SwingTrendFollower EA Initialized Successfully");
   Print("Signal TF: ", EnumToString(InpSignalTimeframe));
   Print("Trend TF: ", EnumToString(InpTrendTimeframe));
   Print("Swing Depth: ", InpSwingDepth);
   Print("Trend Confirmation: ", InpTrendConfirmCount, " consecutive HH/HL or LH/LL");
   Print("Signal Confirmation: ", InpSignalConfirmCount, " consecutive HH/HL or LH/LL");
   Print("Max Positions per Trend: ", InpMaxPositionsPerTrend);
   Print("Historical Trend Swings: ", ArraySize(g_TrendSwings));
   Print("Historical Signal Swings: ", ArraySize(g_SignalSwings));
   Print("Current HTF Trend: ", TrendStateToString(g_TrendInfo.state));
   Print("═══════════════════════════════════════════════════════");

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   //--- Clean up chart objects created by this EA
   ObjectsDeleteAll(0, g_ObjectPrefix);

   Print("SwingTrendFollower EA deinitialized. Reason code: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
   //--- Refresh symbol data
   if(!g_SymbolInfo.RefreshRates())
      return;

   //--- Check for new confirmed swings on both timeframes
   CheckForNewSwings();

   //--- Store previous trend state
   ENUM_TREND_STATE previousTrendState = g_TrendInfo.state;

   //--- Analyze higher timeframe trend
   AnalyzeHTFTrend();

   //--- Handle trend state changes
   if(g_TrendInfo.state != previousTrendState)
   {
      OnTrendStateChanged(previousTrendState, g_TrendInfo.state);
   }

   //--- Check for trend break (real-time, based on bid/ask)
   if(g_TrendInfo.state != TREND_NONE)
   {
      if(CheckTrendBreak())
      {
         HandleTrendBreak();
         return;  // Exit early, trend is broken
      }
   }

   //--- Check for entry signals if trend is active
   if(g_TrendInfo.state != TREND_NONE)
   {
      if(g_TrendInfo.positionsOpened < InpMaxPositionsPerTrend)
      {
         CheckEntrySignal();
      }
   }

   //--- Update trend rectangle if active
   if(InpShowRectangles && g_TrendInfo.state != TREND_NONE)
   {
      UpdateTrendRectangle();
   }
}

//+------------------------------------------------------------------+
//| Trade transaction event handler                                   |
//| Tracks position closures (SL/TP) to update position counter       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result)
{
   //--- Only process deal additions (position opens/closes)
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD)
   {
      //--- Check if this deal is for our symbol
      if(trans.symbol != _Symbol)
         return;

      //--- Get deal info to check if it's from our EA
      if(trans.deal > 0)
      {
         long dealMagic = 0;
         if(HistoryDealSelect(trans.deal))
         {
            dealMagic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
         }

         //--- Only process deals from this EA
         if(dealMagic != (long)InpMagicNumber)
            return;
      }

      //--- Refresh position count after any deal
      int previousCount = g_TrendInfo.positionsOpened;
      int currentPositions = CountEAPositions();

      //--- If positions changed, update and log
      if(currentPositions != previousCount)
      {
         if(currentPositions < previousCount)
         {
            Print("Position closed (SL/TP/Manual). Active positions: ", currentPositions,
                  " (was ", previousCount, ")");
         }
         else
         {
            Print("Position opened. Active positions: ", currentPositions);
         }

         //--- Update counter
         g_TrendInfo.positionsOpened = currentPositions;
      }
   }
}

//+------------------------------------------------------------------+
//| Validate input parameters                                         |
//+------------------------------------------------------------------+
bool ValidateInputs()
{
   bool valid = true;

   if(InpSwingDepth < 1)
   {
      Print("ERROR: Swing Depth must be at least 1");
      valid = false;
   }

   if(InpTrendConfirmCount < 1)
   {
      Print("ERROR: Trend Confirmation Count must be at least 1");
      valid = false;
   }

   if(InpSignalConfirmCount < 1)
   {
      Print("ERROR: Signal Confirmation Count must be at least 1");
      valid = false;
   }

   if(InpRiskAmount <= 0)
   {
      Print("ERROR: Risk Amount must be positive");
      valid = false;
   }

   if(InpMaxPositionsPerTrend < 1)
   {
      Print("ERROR: Max Positions per Trend must be at least 1");
      valid = false;
   }

   if(InpSLValue <= 0)
   {
      Print("ERROR: Stop Loss Value must be positive");
      valid = false;
   }

   if(InpUseTP && InpTPType != TP_NONE && InpTPValue <= 0)
   {
      Print("ERROR: Take Profit Value must be positive when TP is enabled");
      valid = false;
   }

   // Warning for timeframe relationship
   if(PeriodSeconds(InpTrendTimeframe) <= PeriodSeconds(InpSignalTimeframe))
   {
      Print("WARNING: Trend timeframe should be higher than Signal timeframe for optimal results");
   }

   return valid;
}

//+------------------------------------------------------------------+
//| Get appropriate filling mode for the symbol                       |
//+------------------------------------------------------------------+
ENUM_ORDER_TYPE_FILLING GetFillingMode()
{
   uint filling = (uint)SymbolInfoInteger(_Symbol, SYMBOL_FILLING_MODE);

   if((filling & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      return ORDER_FILLING_FOK;

   if((filling & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      return ORDER_FILLING_IOC;

   return ORDER_FILLING_RETURN;
}

//+------------------------------------------------------------------+
//| Load historical swings for both timeframes                        |
//+------------------------------------------------------------------+
bool LoadHistoricalSwings()
{
   int barsToAnalyze = 500;

   //--- Load trend timeframe swings
   bool trendLoaded = LoadSwingsForTimeframe(InpTrendTimeframe, g_TrendSwings, barsToAnalyze, true);

   //--- Load signal timeframe swings
   bool signalLoaded = LoadSwingsForTimeframe(InpSignalTimeframe, g_SignalSwings, barsToAnalyze, false);

   //--- Update last processed bar times
   if(ArraySize(g_TrendSwings) > 0)
   {
      datetime barTimes[];
      if(CopyTime(_Symbol, InpTrendTimeframe, 0, 1, barTimes) > 0)
         g_LastTrendBarTime = barTimes[0];
   }

   if(ArraySize(g_SignalSwings) > 0)
   {
      datetime barTimes[];
      if(CopyTime(_Symbol, InpSignalTimeframe, 0, 1, barTimes) > 0)
         g_LastSignalBarTime = barTimes[0];
   }

   return trendLoaded && signalLoaded;
}

//+------------------------------------------------------------------+
//| Load swings for a specific timeframe                              |
//+------------------------------------------------------------------+
bool LoadSwingsForTimeframe(ENUM_TIMEFRAMES tf, SwingPoint &swings[], int barsToLoad, bool isTrendTF)
{
   double high[], low[];
   datetime time[];

   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(time, true);

   int copied = CopyHigh(_Symbol, tf, 0, barsToLoad, high);
   if(copied <= 0)
   {
      Print("ERROR: Failed to copy High data for ", EnumToString(tf));
      return false;
   }
   barsToLoad = MathMin(barsToLoad, copied);

   if(CopyLow(_Symbol, tf, 0, barsToLoad, low) <= 0)
   {
      Print("ERROR: Failed to copy Low data for ", EnumToString(tf));
      return false;
   }

   if(CopyTime(_Symbol, tf, 0, barsToLoad, time) <= 0)
   {
      Print("ERROR: Failed to copy Time data for ", EnumToString(tf));
      return false;
   }

   //--- Find confirmed swings
   //--- A swing is confirmed when InpSwingDepth bars have formed to its right
   //--- So we start checking from bar index InpSwingDepth (the newest confirmed potential swing)
   //--- and go back to bar barsToLoad - InpSwingDepth - 1 (oldest with enough left context)

   int startBar = InpSwingDepth + 1;  // +1 to skip the bar currently being confirmed
   int endBar = barsToLoad - InpSwingDepth - 1;

   for(int i = endBar; i >= startBar; i--)
   {
      //--- Check for swing high
      if(IsSwingHigh(high, i, barsToLoad))
      {
         AddSwingPoint(swings, time[i], high[i], SWING_HIGH, CreateBarIdentifier(time[i], high[i]), isTrendTF);
      }

      //--- Check for swing low
      if(IsSwingLow(low, i, barsToLoad))
      {
         AddSwingPoint(swings, time[i], low[i], SWING_LOW, CreateBarIdentifier(time[i], low[i]), isTrendTF);
      }
   }

   //--- Draw trend lines
   DrawSwingTrendLines(swings, isTrendTF);

   return true;
}

//+------------------------------------------------------------------+
//| Check if a bar is a swing high                                    |
//+------------------------------------------------------------------+
bool IsSwingHigh(const double &high[], int index, int arraySize)
{
   //--- Boundary check
   if(index < InpSwingDepth || index >= arraySize - InpSwingDepth)
      return false;

   double pivotHigh = high[index];

   //--- Check bars to the left (older bars - higher index in series array)
   for(int i = 1; i <= InpSwingDepth; i++)
   {
      if(high[index + i] >= pivotHigh)
         return false;
   }

   //--- Check bars to the right (newer bars - lower index in series array)
   for(int i = 1; i <= InpSwingDepth; i++)
   {
      if(high[index - i] >= pivotHigh)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check if a bar is a swing low                                     |
//+------------------------------------------------------------------+
bool IsSwingLow(const double &low[], int index, int arraySize)
{
   //--- Boundary check
   if(index < InpSwingDepth || index >= arraySize - InpSwingDepth)
      return false;

   double pivotLow = low[index];

   //--- Check bars to the left (older bars - higher index in series array)
   for(int i = 1; i <= InpSwingDepth; i++)
   {
      if(low[index + i] <= pivotLow)
         return false;
   }

   //--- Check bars to the right (newer bars - lower index in series array)
   for(int i = 1; i <= InpSwingDepth; i++)
   {
      if(low[index - i] <= pivotLow)
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Create unique bar identifier                                      |
//+------------------------------------------------------------------+
long CreateBarIdentifier(datetime time, double price)
{
   //--- Combine time and price into a unique identifier
   return (long)time + (long)(price * 100000);
}

//+------------------------------------------------------------------+
//| Add swing point to array                                          |
//+------------------------------------------------------------------+
void AddSwingPoint(SwingPoint &swings[], datetime time, double price, ENUM_SWING_TYPE type, long barId, bool isTrendTF)
{
   //--- Check if this swing already exists
   int size = ArraySize(swings);
   for(int i = size - 1; i >= MathMax(0, size - 20); i--)
   {
      if(swings[i].barIdentifier == barId)
         return;  // Already exists
   }

   //--- Limit array size
   if(size >= MAX_SWINGS)
   {
      //--- Remove oldest swings
      for(int i = 0; i < size - MAX_SWINGS/2; i++)
      {
         swings[i] = swings[i + MAX_SWINGS/2];
      }
      ArrayResize(swings, size - MAX_SWINGS/2);
      size = ArraySize(swings);
   }

   //--- Add new swing
   ArrayResize(swings, size + 1);
   swings[size].time = time;
   swings[size].price = NormalizeDouble(price, g_SymbolInfo.Digits());
   swings[size].type = type;
   swings[size].barIdentifier = barId;
   swings[size].isDrawn = false;

   //--- Draw the swing point
   DrawSwingPoint(swings[size], isTrendTF);
   swings[size].isDrawn = true;
}

//+------------------------------------------------------------------+
//| Check for new swings on both timeframes                           |
//+------------------------------------------------------------------+
void CheckForNewSwings()
{
   //--- Check trend timeframe
   CheckNewSwingsForTimeframe(InpTrendTimeframe, g_TrendSwings, g_LastTrendBarTime, true);

   //--- Check signal timeframe
   CheckNewSwingsForTimeframe(InpSignalTimeframe, g_SignalSwings, g_LastSignalBarTime, false);
}

//+------------------------------------------------------------------+
//| Check for new swings on a specific timeframe                      |
//+------------------------------------------------------------------+
void CheckNewSwingsForTimeframe(ENUM_TIMEFRAMES tf, SwingPoint &swings[], datetime &lastBarTime, bool isTrendTF)
{
   datetime currentBarTime[];
   ArraySetAsSeries(currentBarTime, true);

   if(CopyTime(_Symbol, tf, 0, 1, currentBarTime) <= 0)
      return;

   //--- Only check when a new bar has formed
   if(currentBarTime[0] <= lastBarTime)
      return;

   lastBarTime = currentBarTime[0];

   //--- Get price data
   double high[], low[];
   datetime time[];

   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(time, true);

   int barsNeeded = InpSwingDepth * 2 + 5;

   if(CopyHigh(_Symbol, tf, 0, barsNeeded, high) < barsNeeded)
      return;
   if(CopyLow(_Symbol, tf, 0, barsNeeded, low) < barsNeeded)
      return;
   if(CopyTime(_Symbol, tf, 0, barsNeeded, time) < barsNeeded)
      return;

   //--- The bar that just got confirmed is at index InpSwingDepth
   //--- (it now has InpSwingDepth bars to its right that have closed)
   int checkIndex = InpSwingDepth;

   bool newSwingAdded = false;

   //--- Check for swing high
   if(IsSwingHigh(high, checkIndex, barsNeeded))
   {
      long barId = CreateBarIdentifier(time[checkIndex], high[checkIndex]);
      int prevSize = ArraySize(swings);
      AddSwingPoint(swings, time[checkIndex], high[checkIndex], SWING_HIGH, barId, isTrendTF);
      if(ArraySize(swings) > prevSize)
         newSwingAdded = true;
   }

   //--- Check for swing low
   if(IsSwingLow(low, checkIndex, barsNeeded))
   {
      long barId = CreateBarIdentifier(time[checkIndex], low[checkIndex]);
      int prevSize = ArraySize(swings);
      AddSwingPoint(swings, time[checkIndex], low[checkIndex], SWING_LOW, barId, isTrendTF);
      if(ArraySize(swings) > prevSize)
         newSwingAdded = true;
   }

   //--- Update trend lines if new swing was added
   if(newSwingAdded)
   {
      DrawSwingTrendLines(swings, isTrendTF);
   }
}

//+------------------------------------------------------------------+
//| Analyze higher timeframe trend                                    |
//+------------------------------------------------------------------+
void AnalyzeHTFTrend()
{
   int size = ArraySize(g_TrendSwings);

   //--- Need at least (x+1) highs and (x+1) lows to confirm a trend
   int minSwingsNeeded = (InpTrendConfirmCount + 1) * 2;

   if(size < minSwingsNeeded)
   {
      g_TrendInfo.state = TREND_NONE;
      return;
   }

   //--- Separate highs and lows
   double highs[];
   double lows[];
   datetime highTimes[];
   datetime lowTimes[];

   ArrayResize(highs, 0);
   ArrayResize(lows, 0);
   ArrayResize(highTimes, 0);
   ArrayResize(lowTimes, 0);

   for(int i = 0; i < size; i++)
   {
      if(g_TrendSwings[i].type == SWING_HIGH)
      {
         int hSize = ArraySize(highs);
         ArrayResize(highs, hSize + 1);
         ArrayResize(highTimes, hSize + 1);
         highs[hSize] = g_TrendSwings[i].price;
         highTimes[hSize] = g_TrendSwings[i].time;
      }
      else
      {
         int lSize = ArraySize(lows);
         ArrayResize(lows, lSize + 1);
         ArrayResize(lowTimes, lSize + 1);
         lows[lSize] = g_TrendSwings[i].price;
         lowTimes[lSize] = g_TrendSwings[i].time;
      }
   }

   int numHighs = ArraySize(highs);
   int numLows = ArraySize(lows);

   if(numHighs < InpTrendConfirmCount + 1 || numLows < InpTrendConfirmCount + 1)
   {
      g_TrendInfo.state = TREND_NONE;
      return;
   }

   //--- Check for uptrend: x consecutive higher highs AND x consecutive higher lows
   bool isUptrend = CheckConsecutiveHigherSwings(highs, numHighs, InpTrendConfirmCount) &&
                    CheckConsecutiveHigherSwings(lows, numLows, InpTrendConfirmCount);

   //--- Check for downtrend: x consecutive lower highs AND x consecutive lower lows
   bool isDowntrend = CheckConsecutiveLowerSwings(highs, numHighs, InpTrendConfirmCount) &&
                      CheckConsecutiveLowerSwings(lows, numLows, InpTrendConfirmCount);

   //--- Update trend info
   if(isUptrend)
   {
      g_TrendInfo.state = TREND_LONG;
      g_TrendInfo.lastHigh = highs[numHighs - 1];
      g_TrendInfo.lastLow = lows[numLows - 1];
      g_TrendInfo.lastHighTime = highTimes[numHighs - 1];
      g_TrendInfo.lastLowTime = lowTimes[numLows - 1];
   }
   else if(isDowntrend)
   {
      g_TrendInfo.state = TREND_SHORT;
      g_TrendInfo.lastHigh = highs[numHighs - 1];
      g_TrendInfo.lastLow = lows[numLows - 1];
      g_TrendInfo.lastHighTime = highTimes[numHighs - 1];
      g_TrendInfo.lastLowTime = lowTimes[numLows - 1];
   }
   else
   {
      g_TrendInfo.state = TREND_NONE;
   }
}

//+------------------------------------------------------------------+
//| Check for consecutive higher swings                               |
//+------------------------------------------------------------------+
bool CheckConsecutiveHigherSwings(const double &prices[], int count, int required)
{
   if(count < required + 1)
      return false;

   for(int i = 0; i < required; i++)
   {
      int idx = count - 1 - i;
      if(prices[idx] <= prices[idx - 1])
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Check for consecutive lower swings                                |
//+------------------------------------------------------------------+
bool CheckConsecutiveLowerSwings(const double &prices[], int count, int required)
{
   if(count < required + 1)
      return false;

   for(int i = 0; i < required; i++)
   {
      int idx = count - 1 - i;
      if(prices[idx] >= prices[idx - 1])
         return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| Handle trend state change                                         |
//+------------------------------------------------------------------+
void OnTrendStateChanged(ENUM_TREND_STATE oldState, ENUM_TREND_STATE newState)
{
   Print("HTF Trend Changed: ", TrendStateToString(oldState), " -> ", TrendStateToString(newState));

   if(newState != TREND_NONE)
   {
      //--- New trend started
      g_TrendInfo.startTime = TimeCurrent();
      g_TrendInfo.positionsOpened = CountEAPositions();
      g_TrendInfo.trendIdentifier = (long)TimeCurrent();

      //--- Draw trend rectangle
      if(InpShowRectangles)
      {
         DrawTrendRectangle();
      }

      //--- Reset entry signal time
      g_LastEntrySignalTime = 0;
   }
   else
   {
      //--- Trend ended
      FinalizeTrendRectangle();
   }
}

//+------------------------------------------------------------------+
//| Check if trend is broken                                          |
//+------------------------------------------------------------------+
bool CheckTrendBreak()
{
   if(g_TrendInfo.state == TREND_NONE)
      return false;

   double bid = g_SymbolInfo.Bid();
   double ask = g_SymbolInfo.Ask();

   //--- Uptrend breaks when bid drops below last low
   if(g_TrendInfo.state == TREND_LONG)
   {
      if(bid < g_TrendInfo.lastLow)
      {
         Print("TREND BREAK: Uptrend broken! Bid (", bid, ") < Last Low (", g_TrendInfo.lastLow, ")");
         return true;
      }
   }
   //--- Downtrend breaks when ask rises above last high
   else if(g_TrendInfo.state == TREND_SHORT)
   {
      if(ask > g_TrendInfo.lastHigh)
      {
         Print("TREND BREAK: Downtrend broken! Ask (", ask, ") > Last High (", g_TrendInfo.lastHigh, ")");
         return true;
      }
   }

   return false;
}

//+------------------------------------------------------------------+
//| Handle trend break - close positions                              |
//+------------------------------------------------------------------+
void HandleTrendBreak()
{
   //--- Close all positions opened by this EA
   CloseAllEAPositions();

   //--- Finalize trend rectangle
   FinalizeTrendRectangle();

   //--- Reset trend info
   ENUM_TREND_STATE brokenTrend = g_TrendInfo.state;
   g_TrendInfo.Reset();

   Print("Trend break handled. Closed all positions. Previous trend: ", TrendStateToString(brokenTrend));
}

//+------------------------------------------------------------------+
//| Check for entry signal on signal timeframe                        |
//+------------------------------------------------------------------+
void CheckEntrySignal()
{
   int size = ArraySize(g_SignalSwings);

   //--- Need at least (y+1) highs and (y+1) lows
   int minSwingsNeeded = (InpSignalConfirmCount + 1) * 2;

   if(size < minSwingsNeeded)
      return;

   //--- Separate highs and lows
   double highs[];
   double lows[];
   datetime highTimes[];
   datetime lowTimes[];

   ArrayResize(highs, 0);
   ArrayResize(lows, 0);
   ArrayResize(highTimes, 0);
   ArrayResize(lowTimes, 0);

   for(int i = 0; i < size; i++)
   {
      if(g_SignalSwings[i].type == SWING_HIGH)
      {
         int hSize = ArraySize(highs);
         ArrayResize(highs, hSize + 1);
         ArrayResize(highTimes, hSize + 1);
         highs[hSize] = g_SignalSwings[i].price;
         highTimes[hSize] = g_SignalSwings[i].time;
      }
      else
      {
         int lSize = ArraySize(lows);
         ArrayResize(lows, lSize + 1);
         ArrayResize(lowTimes, lSize + 1);
         lows[lSize] = g_SignalSwings[i].price;
         lowTimes[lSize] = g_SignalSwings[i].time;
      }
   }

   int numHighs = ArraySize(highs);
   int numLows = ArraySize(lows);

   if(numHighs < InpSignalConfirmCount + 1 || numLows < InpSignalConfirmCount + 1)
      return;

   //--- Get the time of the most recent swing point for signal validation
   datetime latestSwingTime = MathMax(highTimes[numHighs - 1], lowTimes[numLows - 1]);

   //--- Avoid re-triggering on the same signal
   if(latestSwingTime <= g_LastEntrySignalTime)
      return;

   //--- Check for BUY signal: HTF uptrend + Signal TF uptrend
   if(g_TrendInfo.state == TREND_LONG)
   {
      bool signalUptrend = CheckConsecutiveHigherSwings(highs, numHighs, InpSignalConfirmCount) &&
                           CheckConsecutiveHigherSwings(lows, numLows, InpSignalConfirmCount);

      if(signalUptrend)
      {
         Print("BUY SIGNAL detected on Signal TF");
         g_LastEntrySignalTime = latestSwingTime;

         double lastSwingLow = lows[numLows - 1];
         ExecuteBuyTrade(lastSwingLow);
      }
   }
   //--- Check for SELL signal: HTF downtrend + Signal TF downtrend
   else if(g_TrendInfo.state == TREND_SHORT)
   {
      bool signalDowntrend = CheckConsecutiveLowerSwings(highs, numHighs, InpSignalConfirmCount) &&
                             CheckConsecutiveLowerSwings(lows, numLows, InpSignalConfirmCount);

      if(signalDowntrend)
      {
         Print("SELL SIGNAL detected on Signal TF");
         g_LastEntrySignalTime = latestSwingTime;

         double lastSwingHigh = highs[numHighs - 1];
         ExecuteSellTrade(lastSwingHigh);
      }
   }
}

//+------------------------------------------------------------------+
//| Execute buy trade                                                 |
//+------------------------------------------------------------------+
void ExecuteBuyTrade(double lastSwingLow)
{
   g_SymbolInfo.RefreshRates();
   double entryPrice = g_SymbolInfo.Ask();

   //--- Calculate stop loss
   double sl = CalculateStopLoss(ORDER_TYPE_BUY, entryPrice, lastSwingLow);

   if(sl >= entryPrice)
   {
      Print("ERROR: Stop loss (", sl, ") must be below entry price (", entryPrice, ") for BUY");
      return;
   }

   //--- Calculate take profit
   double tp = CalculateTakeProfit(ORDER_TYPE_BUY, entryPrice, sl);

   //--- Calculate lot size
   double lots = CalculateLotSize(ORDER_TYPE_BUY, entryPrice, sl);

   if(lots <= 0)
   {
      Print("ERROR: Invalid lot size calculated");
      return;
   }

   //--- Execute trade
   string comment = StringFormat("SWTF_BUY_%d", g_TrendInfo.trendIdentifier);

   if(g_Trade.Buy(lots, _Symbol, entryPrice, sl, tp, comment))
   {
      g_TrendInfo.positionsOpened++;
      Print("BUY trade opened: ", lots, " lots at ", entryPrice, " | SL: ", sl, " | TP: ", tp);
   }
   else
   {
      Print("ERROR: Failed to open BUY trade. Code: ", g_Trade.ResultRetcode(),
            " - ", g_Trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Execute sell trade                                                |
//+------------------------------------------------------------------+
void ExecuteSellTrade(double lastSwingHigh)
{
   g_SymbolInfo.RefreshRates();
   double entryPrice = g_SymbolInfo.Bid();

   //--- Calculate stop loss
   double sl = CalculateStopLoss(ORDER_TYPE_SELL, entryPrice, lastSwingHigh);

   if(sl <= entryPrice)
   {
      Print("ERROR: Stop loss (", sl, ") must be above entry price (", entryPrice, ") for SELL");
      return;
   }

   //--- Calculate take profit
   double tp = CalculateTakeProfit(ORDER_TYPE_SELL, entryPrice, sl);

   //--- Calculate lot size
   double lots = CalculateLotSize(ORDER_TYPE_SELL, entryPrice, sl);

   if(lots <= 0)
   {
      Print("ERROR: Invalid lot size calculated");
      return;
   }

   //--- Execute trade
   string comment = StringFormat("SWTF_SELL_%d", g_TrendInfo.trendIdentifier);

   if(g_Trade.Sell(lots, _Symbol, entryPrice, sl, tp, comment))
   {
      g_TrendInfo.positionsOpened++;
      Print("SELL trade opened: ", lots, " lots at ", entryPrice, " | SL: ", sl, " | TP: ", tp);
   }
   else
   {
      Print("ERROR: Failed to open SELL trade. Code: ", g_Trade.ResultRetcode(),
            " - ", g_Trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| Calculate stop loss price                                         |
//+------------------------------------------------------------------+
double CalculateStopLoss(ENUM_ORDER_TYPE orderType, double entryPrice, double lastSwing)
{
   double sl = 0;
   double point = g_SymbolInfo.Point();
   int digits = g_SymbolInfo.Digits();

   if(InpSLUseSwing)
   {
      //--- Use last swing as stop loss with buffer
      double buffer = InpSLSwingBuffer * point;

      if(orderType == ORDER_TYPE_BUY)
         sl = lastSwing - buffer;
      else
         sl = lastSwing + buffer;
   }
   else
   {
      switch(InpSLType)
      {
         case SL_POINTS:
            if(orderType == ORDER_TYPE_BUY)
               sl = entryPrice - InpSLValue * point;
            else
               sl = entryPrice + InpSLValue * point;
            break;

         case SL_PERCENT:
            if(orderType == ORDER_TYPE_BUY)
               sl = entryPrice * (1.0 - InpSLValue / 100.0);
            else
               sl = entryPrice * (1.0 + InpSLValue / 100.0);
            break;
      }
   }

   return NormalizeDouble(sl, digits);
}

//+------------------------------------------------------------------+
//| Calculate take profit price                                       |
//+------------------------------------------------------------------+
double CalculateTakeProfit(ENUM_ORDER_TYPE orderType, double entryPrice, double sl)
{
   if(!InpUseTP || InpTPType == TP_NONE)
      return 0;

   double tp = 0;
   double point = g_SymbolInfo.Point();
   int digits = g_SymbolInfo.Digits();

   switch(InpTPType)
   {
      case TP_POINTS:
         if(orderType == ORDER_TYPE_BUY)
            tp = entryPrice + InpTPValue * point;
         else
            tp = entryPrice - InpTPValue * point;
         break;

      case TP_PERCENT:
         if(orderType == ORDER_TYPE_BUY)
            tp = entryPrice * (1.0 + InpTPValue / 100.0);
         else
            tp = entryPrice * (1.0 - InpTPValue / 100.0);
         break;

      default:
         tp = 0;
         break;
   }

   return NormalizeDouble(tp, digits);
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                  |
//+------------------------------------------------------------------+
double CalculateLotSize(ENUM_ORDER_TYPE orderType, double entryPrice, double sl)
{
   double slDistance = MathAbs(entryPrice - sl);
   double point = g_SymbolInfo.Point();

   if(slDistance < point)
   {
      Print("ERROR: Stop loss distance too small (", slDistance, ")");
      return 0;
   }

   //--- Get tick value and tick size
   double tickValue = g_SymbolInfo.TickValue();
   double tickSize = g_SymbolInfo.TickSize();

   if(tickSize <= 0 || tickValue <= 0)
   {
      Print("ERROR: Invalid tick size (", tickSize, ") or tick value (", tickValue, ")");
      return 0;
   }

   //--- Calculate value per point
   double valuePerPoint = tickValue / (tickSize / point);

   if(valuePerPoint <= 0)
   {
      Print("ERROR: Invalid value per point (", valuePerPoint, ")");
      return 0;
   }

   //--- Calculate SL distance in points
   double slPoints = slDistance / point;

   //--- Calculate lot size: Risk / (SL points * value per point per lot)
   double lots = InpRiskAmount / (slPoints * valuePerPoint);

   //--- Normalize lot size
   double minLot = g_SymbolInfo.LotsMin();
   double maxLot = g_SymbolInfo.LotsMax();
   double lotStep = g_SymbolInfo.LotsStep();

   if(lotStep <= 0)
      lotStep = 0.01;

   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, MathMin(maxLot, lots));

   //--- Check margin requirements
   double margin = 0;
   if(!OrderCalcMargin(orderType, _Symbol, lots, entryPrice, margin))
   {
      Print("ERROR: Failed to calculate margin for ", lots, " lots");
      return 0;
   }

   double freeMargin = g_AccountInfo.FreeMargin();
   if(margin > freeMargin)
   {
      Print("WARNING: Not enough margin. Required: ", margin, " | Available: ", freeMargin);

      //--- Try to reduce lot size to fit margin
      double marginPerLot = margin / lots;
      if(marginPerLot > 0)
      {
         lots = MathFloor((freeMargin * 0.9) / marginPerLot / lotStep) * lotStep;
         lots = MathMax(minLot, lots);

         if(!OrderCalcMargin(orderType, _Symbol, lots, entryPrice, margin))
            return 0;

         if(margin > freeMargin)
         {
            Print("ERROR: Still not enough margin even with reduced lot size");
            return 0;
         }

         Print("Lot size reduced to ", lots, " due to margin constraints");
      }
      else
      {
         return 0;
      }
   }

   return lots;
}

//+------------------------------------------------------------------+
//| Close all positions opened by this EA                             |
//+------------------------------------------------------------------+
void CloseAllEAPositions()
{
   int total = PositionsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      if(g_PositionInfo.SelectByIndex(i))
      {
         if(g_PositionInfo.Symbol() == _Symbol && g_PositionInfo.Magic() == InpMagicNumber)
         {
            ulong ticket = g_PositionInfo.Ticket();

            if(g_Trade.PositionClose(ticket))
            {
               Print("Closed position #", ticket);
            }
            else
            {
               Print("ERROR: Failed to close position #", ticket,
                     ". Code: ", g_Trade.ResultRetcode());
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Count positions opened by this EA                                 |
//+------------------------------------------------------------------+
int CountEAPositions()
{
   int count = 0;
   int total = PositionsTotal();

   for(int i = 0; i < total; i++)
   {
      if(g_PositionInfo.SelectByIndex(i))
      {
         if(g_PositionInfo.Symbol() == _Symbol && g_PositionInfo.Magic() == InpMagicNumber)
         {
            count++;
         }
      }
   }

   return count;
}

//+------------------------------------------------------------------+
//| Draw swing point visualization                                    |
//+------------------------------------------------------------------+
void DrawSwingPoint(const SwingPoint &swing, bool isTrendTF)
{
   string tfPrefix = isTrendTF ? "TRD_" : "SIG_";
   string typePrefix = (swing.type == SWING_HIGH) ? "H_" : "L_";
   string uniqueId = TimeToString(swing.time, TIME_DATE|TIME_MINUTES) + "_" +
                     DoubleToString(swing.price, g_SymbolInfo.Digits());

   //--- Colors and sizes
   color arrowColor;
   int arrowCode;
   int arrowSize;

   if(swing.type == SWING_HIGH)
   {
      arrowColor = isTrendTF ? InpTrendHighColor : InpSignalHighColor;
      arrowCode = 218;  // Downward pointing arrow
      arrowSize = isTrendTF ? InpTrendArrowSize : InpSignalArrowSize;
   }
   else
   {
      arrowColor = isTrendTF ? InpTrendLowColor : InpSignalLowColor;
      arrowCode = 217;  // Upward pointing arrow
      arrowSize = isTrendTF ? InpTrendArrowSize : InpSignalArrowSize;
   }

   //--- Draw arrow
   string arrowName = g_ObjectPrefix + tfPrefix + "ARR_" + typePrefix + uniqueId;

   if(ObjectCreate(0, arrowName, OBJ_ARROW, 0, swing.time, swing.price))
   {
      ObjectSetInteger(0, arrowName, OBJPROP_ARROWCODE, arrowCode);
      ObjectSetInteger(0, arrowName, OBJPROP_COLOR, arrowColor);
      ObjectSetInteger(0, arrowName, OBJPROP_WIDTH, arrowSize);
      ObjectSetInteger(0, arrowName, OBJPROP_ANCHOR,
                       swing.type == SWING_HIGH ? ANCHOR_BOTTOM : ANCHOR_TOP);
      ObjectSetInteger(0, arrowName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, arrowName, OBJPROP_HIDDEN, true);
   }

   //--- Draw horizontal price line
   string lineName = g_ObjectPrefix + tfPrefix + "LN_" + typePrefix + uniqueId;
   ENUM_TIMEFRAMES tf = isTrendTF ? InpTrendTimeframe : InpSignalTimeframe;
   datetime lineEnd = swing.time + PeriodSeconds(tf) * 3;

   if(ObjectCreate(0, lineName, OBJ_TREND, 0, swing.time, swing.price, lineEnd, swing.price))
   {
      ObjectSetInteger(0, lineName, OBJPROP_COLOR, arrowColor);
      ObjectSetInteger(0, lineName, OBJPROP_WIDTH, isTrendTF ? 2 : 1);
      ObjectSetInteger(0, lineName, OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, lineName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, lineName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, lineName, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| Draw trend lines connecting swing points                          |
//+------------------------------------------------------------------+
void DrawSwingTrendLines(const SwingPoint &swings[], bool isTrendTF)
{
   int size = ArraySize(swings);
   if(size < 2)
      return;

   string tfPrefix = isTrendTF ? "TRD_" : "SIG_";

   //--- Find last two highs and last two lows
   int highCount = 0, lowCount = 0;
   SwingPoint lastHighs[2], lastLows[2];

   for(int i = size - 1; i >= 0 && (highCount < 2 || lowCount < 2); i--)
   {
      if(swings[i].type == SWING_HIGH && highCount < 2)
      {
         lastHighs[highCount] = swings[i];
         highCount++;
      }
      else if(swings[i].type == SWING_LOW && lowCount < 2)
      {
         lastLows[lowCount] = swings[i];
         lowCount++;
      }
   }

   //--- Draw high trend line
   if(highCount >= 2)
   {
      string highLineName = g_ObjectPrefix + tfPrefix + "TRENDLINE_HIGH";
      color lineColor = (lastHighs[0].price > lastHighs[1].price) ?
                        InpUptrendLineColor : InpDowntrendLineColor;

      ObjectDelete(0, highLineName);

      if(ObjectCreate(0, highLineName, OBJ_TREND, 0,
                      lastHighs[1].time, lastHighs[1].price,
                      lastHighs[0].time, lastHighs[0].price))
      {
         ObjectSetInteger(0, highLineName, OBJPROP_COLOR, lineColor);
         ObjectSetInteger(0, highLineName, OBJPROP_WIDTH, InpTrendLineWidth);
         ObjectSetInteger(0, highLineName, OBJPROP_RAY_RIGHT, true);
         ObjectSetInteger(0, highLineName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, highLineName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, highLineName, OBJPROP_HIDDEN, true);
      }
   }

   //--- Draw low trend line
   if(lowCount >= 2)
   {
      string lowLineName = g_ObjectPrefix + tfPrefix + "TRENDLINE_LOW";
      color lineColor = (lastLows[0].price > lastLows[1].price) ?
                        InpUptrendLineColor : InpDowntrendLineColor;

      ObjectDelete(0, lowLineName);

      if(ObjectCreate(0, lowLineName, OBJ_TREND, 0,
                      lastLows[1].time, lastLows[1].price,
                      lastLows[0].time, lastLows[0].price))
      {
         ObjectSetInteger(0, lowLineName, OBJPROP_COLOR, lineColor);
         ObjectSetInteger(0, lowLineName, OBJPROP_WIDTH, InpTrendLineWidth);
         ObjectSetInteger(0, lowLineName, OBJPROP_RAY_RIGHT, true);
         ObjectSetInteger(0, lowLineName, OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, lowLineName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, lowLineName, OBJPROP_HIDDEN, true);
      }
   }
}

//+------------------------------------------------------------------+
//| Draw trend rectangle                                              |
//+------------------------------------------------------------------+
void DrawTrendRectangle()
{
   if(!InpShowRectangles || g_TrendInfo.state == TREND_NONE)
      return;

   string rectName = g_ObjectPrefix + "TREND_RECT_" + IntegerToString(g_TrendInfo.trendIdentifier);

   //--- Delete existing rectangle if any
   ObjectDelete(0, rectName);

   //--- Get price range
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   int barCount = 50;
   if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, barCount, high) <= 0)
      return;
   if(CopyLow(_Symbol, PERIOD_CURRENT, 0, barCount, low) <= 0)
      return;

   double rectHigh = high[ArrayMaximum(high)];
   double rectLow = low[ArrayMinimum(low)];

   //--- Add padding
   double range = rectHigh - rectLow;
   rectHigh += range * 0.05;
   rectLow -= range * 0.05;

   color rectColor = (g_TrendInfo.state == TREND_LONG) ?
                     InpUptrendRectColor : InpDowntrendRectColor;

   if(ObjectCreate(0, rectName, OBJ_RECTANGLE, 0,
                   g_TrendInfo.startTime, rectHigh,
                   TimeCurrent(), rectLow))
   {
      ObjectSetInteger(0, rectName, OBJPROP_COLOR, rectColor);
      ObjectSetInteger(0, rectName, OBJPROP_FILL, true);
      ObjectSetInteger(0, rectName, OBJPROP_BACK, true);
      ObjectSetInteger(0, rectName, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, rectName, OBJPROP_HIDDEN, true);
   }
}

//+------------------------------------------------------------------+
//| Update trend rectangle                                            |
//+------------------------------------------------------------------+
void UpdateTrendRectangle()
{
   if(!InpShowRectangles || g_TrendInfo.state == TREND_NONE)
      return;

   string rectName = g_ObjectPrefix + "TREND_RECT_" + IntegerToString(g_TrendInfo.trendIdentifier);

   if(ObjectFind(0, rectName) >= 0)
   {
      //--- Update end time
      ObjectSetInteger(0, rectName, OBJPROP_TIME, 1, TimeCurrent());

      //--- Update price range
      double high[], low[];
      ArraySetAsSeries(high, true);
      ArraySetAsSeries(low, true);

      int barCount = Bars(_Symbol, PERIOD_CURRENT, g_TrendInfo.startTime, TimeCurrent());
      barCount = MathMin(barCount, 500);

      if(CopyHigh(_Symbol, PERIOD_CURRENT, 0, barCount, high) > 0 &&
         CopyLow(_Symbol, PERIOD_CURRENT, 0, barCount, low) > 0)
      {
         double rectHigh = high[ArrayMaximum(high)];
         double rectLow = low[ArrayMinimum(low)];
         double range = rectHigh - rectLow;

         ObjectSetDouble(0, rectName, OBJPROP_PRICE, 0, rectHigh + range * 0.05);
         ObjectSetDouble(0, rectName, OBJPROP_PRICE, 1, rectLow - range * 0.05);
      }
   }
}

//+------------------------------------------------------------------+
//| Finalize trend rectangle (stop updating)                          |
//+------------------------------------------------------------------+
void FinalizeTrendRectangle()
{
   if(!InpShowRectangles || g_TrendInfo.trendIdentifier == 0)
      return;

   string rectName = g_ObjectPrefix + "TREND_RECT_" + IntegerToString(g_TrendInfo.trendIdentifier);

   if(ObjectFind(0, rectName) >= 0)
   {
      //--- Set final end time
      ObjectSetInteger(0, rectName, OBJPROP_TIME, 1, TimeCurrent());
   }
}

//+------------------------------------------------------------------+
//| Convert trend state to string                                     |
//+------------------------------------------------------------------+
string TrendStateToString(ENUM_TREND_STATE state)
{
   switch(state)
   {
      case TREND_LONG:  return "UPTREND";
      case TREND_SHORT: return "DOWNTREND";
      default:          return "NO TREND";
   }
}
//+------------------------------------------------------------------+
