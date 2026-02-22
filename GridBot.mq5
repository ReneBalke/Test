//+------------------------------------------------------------------+
//|                                                     GridBot.mq5  |
//|                               IC Trading Grid Bot Expert Advisor  |
//|                                                                    |
//| Strategy: Martingale/DCA-style grid. Opens an initial order, then  |
//| adds positions at percentage-based intervals as price moves         |
//| against the position. Closes all positions when the overall         |
//| break-even price reaches the take-profit threshold.                 |
//|                                                                    |
//| Multi-symbol: Attach to ONE chart — the EA trades all 61 IC        |
//| Trading forex pairs simultaneously. Each symbol is managed by      |
//| its own CGridSymbol instance with independent calculations.         |
//|                                                                    |
//| IC Trading Forex Pairs (61 total):                                 |
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
#property version     "2.00"
#property description "Multi-symbol Martingale/DCA grid bot — attach to one chart"
#property strict

#include <Trade/Trade.mqh>

//--- Input parameters
input double               GridSpacingPercent = 0.5;       // Grid spacing (% of price)
input double               TakeProfitPercent  = 1.0;       // Take profit (% from break-even)
input double               StartingLots       = 0.01;      // Starting lot size
input double               LotIncreaseFactor  = 1.5;       // Lot multiplier per grid level
input int                  MaxGridLevels      = 10;        // Maximum grid levels (safety limit)
input int                  MagicNumber        = 123456;    // Base magic number (each symbol gets +index)

enum ENUM_TRADE_DIRECTION
{
   BUY_ONLY  = 0,  // Buy only
   SELL_ONLY = 1,  // Sell only
   BOTH      = 2   // Both buy and sell
};
input ENUM_TRADE_DIRECTION TradeDirection = BUY_ONLY;      // Trade direction

//+------------------------------------------------------------------+
//| CGridSymbol — encapsulates grid logic for a single symbol         |
//+------------------------------------------------------------------+
class CGridSymbol
{
private:
   string   m_symbol;
   int      m_digits;
   long     m_magicNumber;
   CTrade   m_trade;

public:
   //--- Initialise this instance for one symbol
   bool Init(string symbol, long magicNumber)
   {
      SymbolSelect(symbol, true);
      if(SymbolInfoDouble(symbol, SYMBOL_ASK) <= 0)
         return false;

      m_symbol      = symbol;
      m_digits      = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
      m_magicNumber = magicNumber;

      m_trade.SetExpertMagicNumber(m_magicNumber);
      m_trade.SetMarginMode();
      m_trade.SetTypeFillingBySymbol(m_symbol);

      Print("GridSymbol initialized | Symbol: ", m_symbol,
            " | Magic: ", m_magicNumber);
      return true;
   }

   //--- Called every tick from the global OnTick()
   void OnTick()
   {
      if(TradeDirection == BOTH)
      {
         ProcessDirection(POSITION_TYPE_BUY);
         ProcessDirection(POSITION_TYPE_SELL);
      }
      else if(TradeDirection == BUY_ONLY)
         ProcessDirection(POSITION_TYPE_BUY);
      else
         ProcessDirection(POSITION_TYPE_SELL);
   }

   //--- Core grid logic for one direction
   void ProcessDirection(ENUM_POSITION_TYPE posType)
   {
      int openCount = CountOpenPositions(posType);

      if(openCount == 0)
      {
         double lots = NormalizeLots(StartingLots);
         PlaceGridOrder(posType, lots);
         return;
      }

      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      double breakEven = CalculateBreakEven(posType);
      if(breakEven <= 0) return;

      double tpPrice;
      if(posType == POSITION_TYPE_BUY)
         tpPrice = NormalizeDouble(breakEven * (1.0 + TakeProfitPercent / 100.0), m_digits);
      else
         tpPrice = NormalizeDouble(breakEven * (1.0 - TakeProfitPercent / 100.0), m_digits);

      // Check if take profit is reached
      if(posType == POSITION_TYPE_BUY && ask >= tpPrice)
      {
         Print(m_symbol, " TP reached for BUY grid | Break-even: ", breakEven,
               " | TP: ", tpPrice, " | Ask: ", ask);
         CloseAllPositions(posType);
         return;
      }
      if(posType == POSITION_TYPE_SELL && bid <= tpPrice)
      {
         Print(m_symbol, " TP reached for SELL grid | Break-even: ", breakEven,
               " | TP: ", tpPrice, " | Bid: ", bid);
         CloseAllPositions(posType);
         return;
      }

      // Check if next grid level should be opened
      if(openCount >= MaxGridLevels) return;

      double lastPrice = GetLastOrderPrice(posType);
      if(lastPrice <= 0) return;

      double nextLevel;
      if(posType == POSITION_TYPE_BUY)
         nextLevel = NormalizeDouble(lastPrice * (1.0 - GridSpacingPercent / 100.0), m_digits);
      else
         nextLevel = NormalizeDouble(lastPrice * (1.0 + GridSpacingPercent / 100.0), m_digits);

      bool gridLevelReached = false;
      if(posType == POSITION_TYPE_BUY  && bid <= nextLevel) gridLevelReached = true;
      if(posType == POSITION_TYPE_SELL && ask >= nextLevel) gridLevelReached = true;

      if(gridLevelReached)
      {
         double lots = NormalizeLots(GetNextLotSize(openCount));
         Print(m_symbol, " Grid level ", openCount + 1, " reached for ", EnumToString(posType),
               " | Next level: ", nextLevel, " | Lots: ", lots);
         if(PlaceGridOrder(posType, lots))
            UpdateTakeProfit(posType);
      }
   }

   //--- Count open positions for this symbol + magic + direction
   int CountOpenPositions(ENUM_POSITION_TYPE posType)
   {
      int count = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != posType) continue;
         count++;
      }
      return count;
   }

   //--- Volume-weighted break-even price
   double CalculateBreakEven(ENUM_POSITION_TYPE posType)
   {
      double totalVolume   = 0.0;
      double weightedPrice = 0.0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != posType) continue;

         double lots  = PositionGetDouble(POSITION_VOLUME);
         double price = PositionGetDouble(POSITION_PRICE_OPEN);
         totalVolume   += lots;
         weightedPrice += price * lots;
      }

      if(totalVolume <= 0) return 0.0;
      return NormalizeDouble(weightedPrice / totalVolume, m_digits);
   }

   //--- Open price of the most recently placed order
   double GetLastOrderPrice(ENUM_POSITION_TYPE posType)
   {
      double   lastPrice = 0.0;
      datetime lastTime  = 0;

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;
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

   //--- Lot size for grid level (0-indexed)
   double GetNextLotSize(int level)
   {
      return StartingLots * MathPow(LotIncreaseFactor, (double)level);
   }

   //--- Clamp lots to broker constraints for this symbol
   double NormalizeLots(double lots)
   {
      double minLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      double maxLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      double stepLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

      if(stepLot > 0)
         lots = MathFloor(lots / stepLot) * stepLot;

      lots = MathMax(lots, minLot);
      lots = MathMin(lots, maxLot);
      return NormalizeDouble(lots, 2);
   }

   //--- Place a market order
   bool PlaceGridOrder(ENUM_POSITION_TYPE posType, double lots)
   {
      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      bool result = false;
      if(posType == POSITION_TYPE_BUY)
      {
         result = m_trade.Buy(lots, m_symbol, ask, 0, 0,
                              StringFormat("GridBot BUY L%d", CountOpenPositions(posType) + 1));
      }
      else
      {
         result = m_trade.Sell(lots, m_symbol, bid, 0, 0,
                               StringFormat("GridBot SELL L%d", CountOpenPositions(posType) + 1));
      }

      if(!result)
         Print(m_symbol, " ERROR placing ", EnumToString(posType),
               " order | Error: ", GetLastError(),
               " | RetCode: ", m_trade.ResultRetcode());
      else
         Print(m_symbol, " Opened ", EnumToString(posType),
               " order | Lots: ", lots,
               " | Price: ", (posType == POSITION_TYPE_BUY ? ask : bid));

      return result;
   }

   //--- Recalculate TP from new break-even and update all positions
   void UpdateTakeProfit(ENUM_POSITION_TYPE posType)
   {
      double breakEven = CalculateBreakEven(posType);
      if(breakEven <= 0) return;

      double tpPrice;
      if(posType == POSITION_TYPE_BUY)
         tpPrice = NormalizeDouble(breakEven * (1.0 + TakeProfitPercent / 100.0), m_digits);
      else
         tpPrice = NormalizeDouble(breakEven * (1.0 - TakeProfitPercent / 100.0), m_digits);

      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != posType) continue;

         double sl = PositionGetDouble(POSITION_SL);
         if(!m_trade.PositionModify(ticket, sl, tpPrice))
            Print(m_symbol, " ERROR modifying TP for ticket ", ticket,
                  " | Error: ", GetLastError());
      }
   }

   //--- Close all positions for this symbol/magic/direction
   void CloseAllPositions(ENUM_POSITION_TYPE posType)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;
         if((ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) != posType) continue;

         if(!m_trade.PositionClose(ticket))
            Print(m_symbol, " ERROR closing position ", ticket,
                  " | Error: ", GetLastError(),
                  " | RetCode: ", m_trade.ResultRetcode());
         else
            Print(m_symbol, " Closed position ", ticket, " | ", EnumToString(posType));
      }
   }
};

//+------------------------------------------------------------------+
//| Symbol list — all 61 IC Trading forex pairs                       |
//+------------------------------------------------------------------+
const string g_symbols[] =
{
   // Majors (7)
   "EURUSD","GBPUSD","USDJPY","USDCHF","AUDUSD","USDCAD","NZDUSD",
   // Minors (24)
   "EURGBP","EURJPY","EURCHF","EURAUD","EURCAD","EURNZD",
   "GBPJPY","GBPCHF","GBPAUD","GBPCAD","GBPNZD",
   "AUDJPY","AUDCHF","AUDCAD","AUDNZD",
   "CADJPY","CADCHF","CHFJPY",
   "NZDJPY","NZDCHF","NZDCAD",
   "EURSGD","GBPSGD","AUDSGD",
   // Exotics (30)
   "USDSGD","USDMXN","USDZAR","USDSEK","USDNOK","USDDKK",
   "USDPLN","USDHKD","USDTRY","USDCNH",
   "EURTRY","EURMXN","EURSEK","EURNOK","EURDKK","EURPLN","EURHKD",
   "GBPSEK","GBPNOK","GBPDKK","GBPPLN",
   "SGDJPY","NOKJPY","SEKJPY","DKKJPY",
   "MXNJPY","ZARJPY","TRYJPY","CNHJPY","NZDSGD"
};

//--- One bot instance per symbol; g_botCount tracks how many are active
CGridSymbol g_bots[61];
int         g_botCount = 0;

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

   // Initialise one CGridSymbol per available symbol
   g_botCount = 0;
   int total  = ArraySize(g_symbols);
   for(int i = 0; i < total; i++)
   {
      if(g_bots[g_botCount].Init(g_symbols[i], MagicNumber + g_botCount))
         g_botCount++;
   }

   Print("GridBot v2 initialized | Active symbols: ", g_botCount, "/", total,
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
   Print("GridBot deinitialized | Active bots: ", g_botCount, " | Reason: ", reason);
}

//+------------------------------------------------------------------+
//| Expert tick function — drives all symbol bots on every tick       |
//+------------------------------------------------------------------+
void OnTick()
{
   for(int i = 0; i < g_botCount; i++)
      g_bots[i].OnTick();
}
//+------------------------------------------------------------------+
