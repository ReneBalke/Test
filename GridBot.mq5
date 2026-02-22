//+------------------------------------------------------------------+
//|                                                     GridBot.mq5  |
//|                               IC Trading Grid Bot Expert Advisor  |
//|                                                                    |
//| Strategy: Martingale/DCA-style grid. Opens an initial order, then  |
//| adds positions at percentage-based intervals as price moves         |
//| against the position. Closes all positions when the overall         |
//| break-even price reaches the take-profit threshold.                 |
//|                                                                    |
//| IC Trading Forex Pairs (61 total) - attach EA to each pair:        |
//|                                                                    |
//| Majors (7):                                                        |
//|   EURUSD, GBPUSD, USDJPY, USDCHF, AUDUSD, USDCAD, NZDUSD          |
//|                                                                    |
//| Minors (24):                                                       |
//|   EURGBP, EURJPY, EURCHF, EURAUD, EURCAD, EURNZD                  |
//|   GBPJPY, GBPCHF, GBPAUD, GBPCAD, GBPNZD                          |
//|   AUDJPY, AUDCHF, AUDCAD, AUDNZD                                   |
//|   CADJPY, CADCHF, CHFJPY                                           |
//|   NZDJPY, NZDCHF, NZDCAD                                           |
//|   EURSGD, GBPSGD, AUDSGD                                           |
//|                                                                    |
//| Exotics (30):                                                      |
//|   USDSGD, USDMXN, USDZAR, USDSEK, USDNOK, USDDKK                  |
//|   USDPLN, USDHKD, USDTRY, USDCNH                                   |
//|   EURTRY, EURMXN, EURSEK, EURNOK, EURDKK, EURPLN, EURHKD          |
//|   GBPSEK, GBPNOK, GBPDKK, GBPPLN                                   |
//|   SGDJPY, NOKJPY, SEKJPY, DKKJPY                                   |
//|   MXNJPY, ZARJPY, TRYJPY, CNHJPY, NZDSGD                          |
//+------------------------------------------------------------------+
#property copyright   "IC Trading Grid Bot"
#property version     "1.00"
#property description "Martingale/DCA grid bot for IC Trading forex pairs"
#property strict

#include <Trade/Trade.mqh>

//--- Input parameters
input double               GridSpacingPercent = 0.5;       // Grid spacing (% of price)
input double               TakeProfitPercent  = 1.0;       // Take profit (% from break-even)
input double               StartingLots       = 0.01;      // Starting lot size
input double               LotIncreaseFactor  = 1.5;       // Lot multiplier per grid level
input int                  MaxGridLevels      = 10;        // Maximum grid levels (safety limit)
input int                  MagicNumber        = 123456;    // EA magic number

enum ENUM_TRADE_DIRECTION
{
   BUY_ONLY  = 0,  // Buy only
   SELL_ONLY = 1,  // Sell only
   BOTH      = 2   // Both buy and sell
};
input ENUM_TRADE_DIRECTION TradeDirection = BUY_ONLY;      // Trade direction

//--- Global variables
CTrade  g_trade;
string  g_symbol;
int     g_digits;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   // Validate inputs
   if(GridSpacingPercent <= 0)
   {
      Print("ERROR: GridSpacingPercent must be > 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(TakeProfitPercent <= 0)
   {
      Print("ERROR: TakeProfitPercent must be > 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(StartingLots <= 0)
   {
      Print("ERROR: StartingLots must be > 0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(LotIncreaseFactor < 1.0)
   {
      Print("ERROR: LotIncreaseFactor must be >= 1.0");
      return INIT_PARAMETERS_INCORRECT;
   }
   if(MaxGridLevels < 1)
   {
      Print("ERROR: MaxGridLevels must be >= 1");
      return INIT_PARAMETERS_INCORRECT;
   }

   // Cache symbol info
   g_symbol  = _Symbol;
   g_digits  = _Digits;

   // Configure trade object
   g_trade.SetExpertMagicNumber(MagicNumber);
   g_trade.SetMarginMode();
   g_trade.SetTypeFillingBySymbol(g_symbol);

   Print("GridBot initialized on ", g_symbol,
         " | Spacing: ", GridSpacingPercent, "%",
         " | TP: ", TakeProfitPercent, "%",
         " | StartLots: ", StartingLots,
         " | LotFactor: ", LotIncreaseFactor,
         " | MaxLevels: ", MaxGridLevels,
         " | Direction: ", EnumToString(TradeDirection));

   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Print("GridBot deinitialized on ", g_symbol, " | Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   if(TradeDirection == BOTH)
   {
      ProcessDirection(POSITION_TYPE_BUY);
      ProcessDirection(POSITION_TYPE_SELL);
   }
   else if(TradeDirection == BUY_ONLY)
   {
      ProcessDirection(POSITION_TYPE_BUY);
   }
   else
   {
      ProcessDirection(POSITION_TYPE_SELL);
   }
}

//+------------------------------------------------------------------+
//| Process grid logic for one direction                               |
//+------------------------------------------------------------------+
void ProcessDirection(ENUM_POSITION_TYPE posType)
{
   int openCount = CountOpenPositions(posType);

   if(openCount == 0)
   {
      // No positions open — start the grid with the first order
      double lots = NormalizeLots(StartingLots);
      PlaceGridOrder(posType, lots);
      return;
   }

   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);

   // Calculate current break-even and take-profit price
   double breakEven = CalculateBreakEven(posType);
   if(breakEven <= 0) return;

   double tpPrice;
   if(posType == POSITION_TYPE_BUY)
      tpPrice = NormalizeDouble(breakEven * (1.0 + TakeProfitPercent / 100.0), g_digits);
   else
      tpPrice = NormalizeDouble(breakEven * (1.0 - TakeProfitPercent / 100.0), g_digits);

   // Check if take profit is reached
   if(posType == POSITION_TYPE_BUY && ask >= tpPrice)
   {
      Print("TP reached for BUY grid | Break-even: ", breakEven, " | TP: ", tpPrice, " | Ask: ", ask);
      CloseAllPositions(posType);
      return;
   }
   if(posType == POSITION_TYPE_SELL && bid <= tpPrice)
   {
      Print("TP reached for SELL grid | Break-even: ", breakEven, " | TP: ", tpPrice, " | Bid: ", bid);
      CloseAllPositions(posType);
      return;
   }

   // Check if next grid level should be opened
   if(openCount >= MaxGridLevels) return;

   double lastPrice = GetLastOrderPrice(posType);
   if(lastPrice <= 0) return;

   double nextLevel;
   if(posType == POSITION_TYPE_BUY)
      nextLevel = NormalizeDouble(lastPrice * (1.0 - GridSpacingPercent / 100.0), g_digits);
   else
      nextLevel = NormalizeDouble(lastPrice * (1.0 + GridSpacingPercent / 100.0), g_digits);

   bool gridLevelReached = false;
   if(posType == POSITION_TYPE_BUY && bid <= nextLevel)
      gridLevelReached = true;
   if(posType == POSITION_TYPE_SELL && ask >= nextLevel)
      gridLevelReached = true;

   if(gridLevelReached)
   {
      double lots = NormalizeLots(GetNextLotSize(openCount));
      Print("Grid level ", openCount + 1, " reached for ", EnumToString(posType),
            " | Next level: ", nextLevel, " | Lots: ", lots);
      if(PlaceGridOrder(posType, lots))
         UpdateTakeProfit(posType);
   }
}

//+------------------------------------------------------------------+
//| Count open positions for this EA and direction                     |
//+------------------------------------------------------------------+
int CountOpenPositions(ENUM_POSITION_TYPE posType)
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != posType) continue;
      count++;
   }
   return count;
}

//+------------------------------------------------------------------+
//| Calculate weighted break-even price                                |
//+------------------------------------------------------------------+
double CalculateBreakEven(ENUM_POSITION_TYPE posType)
{
   double totalVolume    = 0.0;
   double weightedPrice  = 0.0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != posType) continue;

      double lots  = PositionGetDouble(POSITION_VOLUME);
      double price = PositionGetDouble(POSITION_PRICE_OPEN);
      totalVolume   += lots;
      weightedPrice += price * lots;
   }

   if(totalVolume <= 0) return 0.0;
   return NormalizeDouble(weightedPrice / totalVolume, g_digits);
}

//+------------------------------------------------------------------+
//| Get the open price of the most recently placed order               |
//+------------------------------------------------------------------+
double GetLastOrderPrice(ENUM_POSITION_TYPE posType)
{
   double lastPrice = 0.0;
   datetime lastTime = 0;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != posType) continue;

      datetime posTime = (datetime)PositionGetInteger(POSITION_TIME);
      if(posTime >= lastTime)
      {
         lastTime  = posTime;
         lastPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      }
   }
   return lastPrice;
}

//+------------------------------------------------------------------+
//| Calculate lot size for a given grid level (0-indexed)              |
//+------------------------------------------------------------------+
double GetNextLotSize(int level)
{
   return StartingLots * MathPow(LotIncreaseFactor, (double)level);
}

//+------------------------------------------------------------------+
//| Normalize lot size to broker constraints                           |
//+------------------------------------------------------------------+
double NormalizeLots(double lots)
{
   double minLot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);
   double stepLot = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);

   if(stepLot > 0)
      lots = MathFloor(lots / stepLot) * stepLot;

   lots = MathMax(lots, minLot);
   lots = MathMin(lots, maxLot);
   return NormalizeDouble(lots, 2);
}

//+------------------------------------------------------------------+
//| Place a market order                                               |
//+------------------------------------------------------------------+
bool PlaceGridOrder(ENUM_POSITION_TYPE posType, double lots)
{
   double ask = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(g_symbol, SYMBOL_BID);

   bool result = false;
   if(posType == POSITION_TYPE_BUY)
   {
      result = g_trade.Buy(lots, g_symbol, ask, 0, 0,
                           StringFormat("GridBot BUY L%d", CountOpenPositions(posType) + 1));
   }
   else
   {
      result = g_trade.Sell(lots, g_symbol, bid, 0, 0,
                            StringFormat("GridBot SELL L%d", CountOpenPositions(posType) + 1));
   }

   if(!result)
      Print("ERROR placing ", EnumToString(posType), " order | Error: ", GetLastError(),
            " | RetCode: ", g_trade.ResultRetcode());
   else
      Print("Opened ", EnumToString(posType), " order | Lots: ", lots,
            " | Price: ", (posType == POSITION_TYPE_BUY ? ask : bid));

   return result;
}

//+------------------------------------------------------------------+
//| Update take-profit on all open positions for the given direction   |
//+------------------------------------------------------------------+
void UpdateTakeProfit(ENUM_POSITION_TYPE posType)
{
   double breakEven = CalculateBreakEven(posType);
   if(breakEven <= 0) return;

   double tpPrice;
   if(posType == POSITION_TYPE_BUY)
      tpPrice = NormalizeDouble(breakEven * (1.0 + TakeProfitPercent / 100.0), g_digits);
   else
      tpPrice = NormalizeDouble(breakEven * (1.0 - TakeProfitPercent / 100.0), g_digits);

   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != posType) continue;

      double sl = PositionGetDouble(POSITION_SL);
      if(!g_trade.PositionModify(ticket, sl, tpPrice))
         Print("ERROR modifying TP for ticket ", ticket, " | Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
//| Close all open positions for the given direction                   |
//+------------------------------------------------------------------+
void CloseAllPositions(ENUM_POSITION_TYPE posType)
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
      if((long)PositionGetInteger(POSITION_MAGIC) != MagicNumber) continue;
      if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != posType) continue;

      if(!g_trade.PositionClose(ticket))
         Print("ERROR closing position ", ticket, " | Error: ", GetLastError(),
               " | RetCode: ", g_trade.ResultRetcode());
      else
         Print("Closed position ", ticket, " | ", EnumToString(posType));
   }
}
//+------------------------------------------------------------------+
