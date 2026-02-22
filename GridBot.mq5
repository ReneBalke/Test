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
#property version     "3.00"
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
//| Per-direction state populated by a single ScanPositions() pass    |
//+------------------------------------------------------------------+
struct SDirectionState
{
   int      count;        // number of open positions
   double   breakEven;    // volume-weighted average open price
   double   lastPrice;    // open price of the most-recent position
   datetime lastTime;     // timestamp of most-recent position (internal)
   double   totalVolume;  // sum of lots (for incremental break-even update)
   ulong    tickets[];    // position tickets (for TP update / close)
};

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

   //--- Cached static symbol constraints (set once in Init, never change)
   double   m_minLot;
   double   m_maxLot;
   double   m_stepLot;

   //--- Single pass: fill buy and sell state from the global position list
   void ScanPositions(SDirectionState &buy, SDirectionState &sell)
   {
      buy.count       = 0; buy.breakEven  = 0; buy.lastPrice  = 0;
      buy.lastTime    = 0; buy.totalVolume = 0; ArrayResize(buy.tickets,  0);
      sell.count      = 0; sell.breakEven = 0; sell.lastPrice = 0;
      sell.lastTime   = 0; sell.totalVolume = 0; ArrayResize(sell.tickets, 0);

      int total = PositionsTotal();
      for(int i = total - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0)                                         continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol)     continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;

         ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
         double   lots    = PositionGetDouble(POSITION_VOLUME);
         double   price   = PositionGetDouble(POSITION_PRICE_OPEN);
         datetime ptime   = (datetime)PositionGetInteger(POSITION_TIME);

         if(ptype == POSITION_TYPE_BUY)
         {
            buy.count++;
            buy.totalVolume += lots;
            buy.breakEven   += price * lots;
            if(ptime >= buy.lastTime) { buy.lastTime = ptime; buy.lastPrice = price; }
            int sz = ArraySize(buy.tickets);
            ArrayResize(buy.tickets, sz + 1);
            buy.tickets[sz] = ticket;
         }
         else
         {
            sell.count++;
            sell.totalVolume += lots;
            sell.breakEven   += price * lots;
            if(ptime >= sell.lastTime) { sell.lastTime = ptime; sell.lastPrice = price; }
            int sz = ArraySize(sell.tickets);
            ArrayResize(sell.tickets, sz + 1);
            sell.tickets[sz] = ticket;
         }
      }

      if(buy.totalVolume  > 0) buy.breakEven  = NormalizeDouble(buy.breakEven  / buy.totalVolume,  m_digits);
      if(sell.totalVolume > 0) sell.breakEven = NormalizeDouble(sell.breakEven / sell.totalVolume, m_digits);
   }

   //--- Lot size for grid level (0-indexed)
   double GetNextLotSize(int level)
   {
      return StartingLots * MathPow(LotIncreaseFactor, (double)level);
   }

   //--- Clamp lots to cached broker constraints
   double NormalizeLots(double lots)
   {
      if(m_stepLot > 0)
         lots = MathFloor(lots / m_stepLot) * m_stepLot;
      lots = MathMax(lots, m_minLot);
      lots = MathMin(lots, m_maxLot);
      return NormalizeDouble(lots, 2);
   }

   //--- Place a market order; returns execution price (0 on failure)
   double PlaceGridOrder(ENUM_POSITION_TYPE posType, double lots,
                         double ask, double bid, int gridLevel)
   {
      bool result = false;
      double execPrice = 0;

      if(posType == POSITION_TYPE_BUY)
      {
         execPrice = ask;
         result = m_trade.Buy(lots, m_symbol, ask, 0, 0,
                              StringFormat("GridBot BUY L%d", gridLevel));
      }
      else
      {
         execPrice = bid;
         result = m_trade.Sell(lots, m_symbol, bid, 0, 0,
                               StringFormat("GridBot SELL L%d", gridLevel));
      }

      if(!result)
      {
         Print(m_symbol, " ERROR placing ", EnumToString(posType),
               " order | Error: ", GetLastError(),
               " | RetCode: ", m_trade.ResultRetcode());
         return 0;
      }

      Print(m_symbol, " Opened ", EnumToString(posType),
            " order | Lots: ", lots, " | Price: ", execPrice);
      return execPrice;
   }

   //--- Update TP on all tickets in state + one optional extra ticket
   void UpdateTakeProfitFromState(const SDirectionState &state,
                                  double tpPrice, ulong extraTicket = 0)
   {
      int sz = ArraySize(state.tickets);
      for(int i = 0; i < sz; i++)
      {
         double sl = 0;
         if(PositionSelectByTicket(state.tickets[i]))
            sl = PositionGetDouble(POSITION_SL);
         if(!m_trade.PositionModify(state.tickets[i], sl, tpPrice))
            Print(m_symbol, " ERROR modifying TP for ticket ", state.tickets[i],
                  " | Error: ", GetLastError());
      }
      if(extraTicket != 0)
      {
         double sl = 0;
         if(PositionSelectByTicket(extraTicket))
            sl = PositionGetDouble(POSITION_SL);
         if(!m_trade.PositionModify(extraTicket, sl, tpPrice))
            Print(m_symbol, " ERROR modifying TP for new ticket ", extraTicket,
                  " | Error: ", GetLastError());
      }
   }

   //--- Close all positions listed in state
   void CloseAllPositions(const SDirectionState &state, ENUM_POSITION_TYPE posType)
   {
      int sz = ArraySize(state.tickets);
      for(int i = sz - 1; i >= 0; i--)
      {
         if(!m_trade.PositionClose(state.tickets[i]))
            Print(m_symbol, " ERROR closing position ", state.tickets[i],
                  " | Error: ", GetLastError(),
                  " | RetCode: ", m_trade.ResultRetcode());
         else
            Print(m_symbol, " Closed position ", state.tickets[i],
                  " | ", EnumToString(posType));
      }
   }

   //--- Core grid logic; all inputs pre-computed — no extra scans
   void ProcessDirection(ENUM_POSITION_TYPE posType, SDirectionState &state,
                         double ask, double bid)
   {
      if(state.count == 0)
      {
         double lots = NormalizeLots(StartingLots);
         PlaceGridOrder(posType, lots, ask, bid, 1);
         return;
      }

      if(state.breakEven <= 0) return;

      double tpPrice = (posType == POSITION_TYPE_BUY)
         ? NormalizeDouble(state.breakEven * (1.0 + TakeProfitPercent / 100.0), m_digits)
         : NormalizeDouble(state.breakEven * (1.0 - TakeProfitPercent / 100.0), m_digits);

      // Check if take profit is reached
      if(posType == POSITION_TYPE_BUY && ask >= tpPrice)
      {
         Print(m_symbol, " TP reached BUY | BE: ", state.breakEven,
               " | TP: ", tpPrice, " | Ask: ", ask);
         CloseAllPositions(state, posType);
         return;
      }
      if(posType == POSITION_TYPE_SELL && bid <= tpPrice)
      {
         Print(m_symbol, " TP reached SELL | BE: ", state.breakEven,
               " | TP: ", tpPrice, " | Bid: ", bid);
         CloseAllPositions(state, posType);
         return;
      }

      if(state.count >= MaxGridLevels || state.lastPrice <= 0) return;

      double nextLevel = (posType == POSITION_TYPE_BUY)
         ? NormalizeDouble(state.lastPrice * (1.0 - GridSpacingPercent / 100.0), m_digits)
         : NormalizeDouble(state.lastPrice * (1.0 + GridSpacingPercent / 100.0), m_digits);

      bool gridLevelReached = (posType == POSITION_TYPE_BUY  && bid <= nextLevel) ||
                              (posType == POSITION_TYPE_SELL && ask >= nextLevel);

      if(!gridLevelReached) return;

      double newLots = NormalizeLots(GetNextLotSize(state.count));
      Print(m_symbol, " Grid level ", state.count + 1, " | ",
            EnumToString(posType), " | NextLevel: ", nextLevel, " | Lots: ", newLots);

      double execPrice = PlaceGridOrder(posType, newLots, ask, bid, state.count + 1);
      if(execPrice <= 0) return;

      // Compute new break-even incrementally — no rescan needed
      double newBE = NormalizeDouble(
         (state.breakEven * state.totalVolume + execPrice * newLots)
         / (state.totalVolume + newLots), m_digits);

      double newTP = (posType == POSITION_TYPE_BUY)
         ? NormalizeDouble(newBE * (1.0 + TakeProfitPercent / 100.0), m_digits)
         : NormalizeDouble(newBE * (1.0 - TakeProfitPercent / 100.0), m_digits);

      // Get new position ticket via the order result
      ulong newTicket = m_trade.ResultOrder();

      UpdateTakeProfitFromState(state, newTP, newTicket);
   }

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

      // Cache static constraints once
      m_minLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      m_maxLot  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      m_stepLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);

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
      SDirectionState buyState, sellState;
      ScanPositions(buyState, sellState);   // single pass — fills both directions

      double ask = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(m_symbol, SYMBOL_BID);

      if(TradeDirection != SELL_ONLY) ProcessDirection(POSITION_TYPE_BUY,  buyState,  ask, bid);
      if(TradeDirection != BUY_ONLY)  ProcessDirection(POSITION_TYPE_SELL, sellState, ask, bid);
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
   if(GridSpacingPercent <= 0)  { Print("ERROR: GridSpacingPercent must be > 0");  return INIT_PARAMETERS_INCORRECT; }
   if(TakeProfitPercent  <= 0)  { Print("ERROR: TakeProfitPercent must be > 0");   return INIT_PARAMETERS_INCORRECT; }
   if(StartingLots       <= 0)  { Print("ERROR: StartingLots must be > 0");        return INIT_PARAMETERS_INCORRECT; }
   if(LotIncreaseFactor  < 1.0) { Print("ERROR: LotIncreaseFactor must be >= 1.0"); return INIT_PARAMETERS_INCORRECT; }
   if(MaxGridLevels      < 1)   { Print("ERROR: MaxGridLevels must be >= 1");      return INIT_PARAMETERS_INCORRECT; }

   g_botCount = 0;
   int total  = ArraySize(g_symbols);
   for(int i = 0; i < total; i++)
   {
      if(g_bots[g_botCount].Init(g_symbols[i], MagicNumber + g_botCount))
         g_botCount++;
   }

   Print("GridBot v3 initialized | Active symbols: ", g_botCount, "/", total,
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
