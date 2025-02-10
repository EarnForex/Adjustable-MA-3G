//+------------------------------------------------------------------+
//|                         Adjustable 3rd Generation Moving Average |
//|                             Copyright © 2011-2025, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2011-2025, EarnForex"
#property link      "https://www.earnforex.com/metatrader-expert-advisors/Adjustable-MA-3G/"
#property version   "1.04"
#property strict

#property description "Adjustable MA 3G EA - expert advisor for customizable MA trading."
#property description "Uses 3rd Generation Moving Average indicator."
#property description "Modify StopLoss, TakeProfit, TrailingStop, MA Period, MA Type"
#property description "and minimum difference between MAs to count as cross."
#property icon "\\Files\\EF-Icon-64x64px.ico"

enum ENUM_TRADE_DIRECTION
{
    TRADE_DIRECTION_LONG, // Long-only
    TRADE_DIRECTION_SHORT, // Short-only
    TRADE_DIRECTION_BOTH // Both
};

input group "Main"
input double Lots      = 0.1;
input int StopLoss     = 170;
input int TakeProfit   = 60;
input int TrailingStop = 0;
input int Period_1  = 35;
input int Period_2  = 30;
input int Period_Sampling_Slow  = 160;
input int Period_Sampling_Fast  = 196;
input ENUM_MA_METHOD MA_Method_Slow = MODE_EMA;
input ENUM_MA_METHOD MA_Method_Fast = MODE_EMA;
input ENUM_APPLIED_PRICE MA_Applied_Price_Slow = PRICE_TYPICAL;
input ENUM_APPLIED_PRICE MA_Applied_Price_Fast = PRICE_TYPICAL;
// The minimum difference between MAs for Cross to count.
input int MinDiff = 1;
input ENUM_TRADE_DIRECTION TradeDirection = TRADE_DIRECTION_BOTH;
input string StartTime = "00:00"; // Start time (Server), inclusive
input string EndTime =   "23:59"; // End time (Server), inclusive
input bool CloseTradesOutsideTradingTime = true;
input bool DoTrailingOutsideTradingTime = true;
input group "Money management"
input bool UseMM = false;
// Amount of lots per every 10,000 of free margin.
input double LotsPer10000 = 1;
input group "Miscellaneous"
input int Slippage = 3;
input string OrderCommentary = "Adjustable MA 3G";

// These depends on broker's quotes.
double Poin;
int Deviation;

int LastBars = 0;

// 0 - undefined, 1 - bullish cross (fast MA above slow MA), -1 - bearish cross (fast MA below slow MA).
int PrevCross = 0;

int Magic;
bool CanTrade = false;

ENUM_SYMBOL_TRADE_EXECUTION Execution_Mode;

int SlowMA;
int FastMA;

int OnInit()
{
    FastMA = MathMin(Period_1, Period_2);
    SlowMA = MathMax(Period_1, Period_2);

    if (FastMA == SlowMA)
    {
        Print("MA periods should differ.");
        return INIT_FAILED;
    }
    if (Period_Sampling_Slow < SlowMA * 4)
    {
        Print("Period_Sampling_Slow should be >= Period_Slow * 4.");
        return INIT_FAILED;
    }
    if (Period_Sampling_Fast < FastMA * 4)
    {
        Print("Period_Sampling_Fast should be >= Period_Fast * 4.");
        return INIT_FAILED;
    }

    Poin = Point;
    Deviation = Slippage;
    // Checking for unconventional Point digits number.
    if ((Point == 0.00001) || (Point == 0.001))
    {
        Poin *= 10;
        Deviation *= 10;
    }

    Magic = Period() + 29472394;

    return INIT_SUCCEEDED;
}

void OnTick()
{
    CanTrade = CheckTime();

    if ((TrailingStop > 0) && ((CanTrade) || (DoTrailingOutsideTradingTime))) DoTrailing();

    // Wait for the new bar in a chart.
    if (LastBars == Bars) return;
    else LastBars = Bars;

    if ((Bars < Period_Sampling_Slow) || (IsTradeAllowed() == false)) return;

    Execution_Mode = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_EXEMODE);

    CheckCross();
}

//+------------------------------------------------------------------+
//| Check for cross and open/close the positions respectively.       |
//+------------------------------------------------------------------+
void CheckCross()
{
    double FMA_Current = iCustom(NULL, 0, "3rdGenMA", FastMA, Period_Sampling_Fast, MA_Method_Fast, MA_Applied_Price_Fast, 0, 1);
    double SMA_Current = iCustom(NULL, 0, "3rdGenMA", SlowMA, Period_Sampling_Slow, MA_Method_Slow, MA_Applied_Price_Slow, 0, 1);

    if (PrevCross == 0) // Was undefined.
    {
        if ((FMA_Current - SMA_Current) >= MinDiff * Poin) PrevCross = 1; // Bullish state.
        else if ((SMA_Current - FMA_Current) >= MinDiff * Poin) PrevCross = -1; // Bearish state.
        return;
    }
    else if (PrevCross == 1) // Was bullish.
    {
        if ((SMA_Current - FMA_Current) >= MinDiff * Poin) //Became bearish
        {
            if ((CanTrade) || (CloseTradesOutsideTradingTime)) ClosePrev();
            if ((CanTrade) && (TradeDirection != TRADE_DIRECTION_LONG)) fSell();
            PrevCross = -1;
        }
    }
    else if (PrevCross == -1) // Was bearish.
    {
        if ((FMA_Current - SMA_Current) >= MinDiff * Poin) //Became bullish
        {
            if ((CanTrade) || (CloseTradesOutsideTradingTime)) ClosePrev();
            if ((CanTrade) && (TradeDirection != TRADE_DIRECTION_SHORT)) fBuy();
            PrevCross = 1;
        }
    }
}

//+------------------------------------------------------------------+
//| Close previous position                                          |
//+------------------------------------------------------------------+
void ClosePrev()
{
    int total = OrdersTotal();
    for (int i = 0; i < total; i++)
    {
        if (OrderSelect(i, SELECT_BY_POS) == false) continue;
        if ((OrderSymbol() == Symbol()) && (OrderMagicNumber() == Magic))
        {
            if (OrderType() == OP_BUY)
            {
                // 10 attempts to close.
                for (int j = 0; j < 10; j++)
                {
                    RefreshRates();
                    if (OrderClose(OrderTicket(), OrderLots(), Bid, Deviation)) break;
                    else Print("Failed to close a Buy order #", OrderTicket(), ", error: ", GetLastError());
                }
            }
            else if (OrderType() == OP_SELL)
            {
                // 10 attempts to close.
                for (int j = 0; j < 10; j++)
                {
                    RefreshRates();
                    if (OrderClose(OrderTicket(), OrderLots(), Ask, Deviation)) break;
                    else Print("Failed to close a Sell order #", OrderTicket(), ", error: ", GetLastError());
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Sell                                                             |
//+------------------------------------------------------------------+
int fSell()
{
    double SL = 0, TP = 0;

    for (int i = 0; i < 10; i++)
    {
        RefreshRates();
        if (Execution_Mode != SYMBOL_TRADE_EXECUTION_MARKET)
        {
            if (StopLoss > 0) SL = Bid + StopLoss * Poin;
            if (TakeProfit > 0) TP = Bid - TakeProfit * Poin;
        }
        int result = OrderSend(Symbol(), OP_SELL, LotsOptimized(), Bid, Deviation, SL, TP, OrderCommentary, Magic);
    
        if (result == -1)
        {
            int e = GetLastError();
            Print("OrderSend error: ", e);
        }
        else
        {
            if (Execution_Mode == SYMBOL_TRADE_EXECUTION_MARKET)
            {
                RefreshRates();
                if (!OrderSelect(result, SELECT_BY_TICKET))
                {
                    Print("Failed to select an order #", result, " for post-open SL/TP application, error: ", GetLastError());
                    return -1;
                }
                if (StopLoss > 0) SL = OrderOpenPrice() + StopLoss * Poin;
                if (TakeProfit > 0) TP = OrderOpenPrice() - TakeProfit * Poin;
                if ((SL != 0) || (TP != 0))
                {
                    if (!OrderModify(result, OrderOpenPrice(), SL, TP, 0))
                    {
                        Print("Failed to modify an order #", result, " (applying post-open SL/TP), error: ", GetLastError());
                        return -1;
                    }
                }
            }
            return result;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Buy                                                              |
//+------------------------------------------------------------------+
int fBuy()
{
    double SL = 0, TP = 0;

    for (int i = 0; i < 10; i++)
    {
        RefreshRates();
        if (Execution_Mode != SYMBOL_TRADE_EXECUTION_MARKET)
        {
            if (StopLoss > 0) SL = Ask - StopLoss * Poin;
            if (TakeProfit > 0) TP = Ask + TakeProfit * Poin;
        }
        int result = OrderSend(Symbol(), OP_BUY, LotsOptimized(), Ask, Deviation, SL, TP, OrderCommentary, Magic);

        if (result == -1)
        {
            int e = GetLastError();
            Print("OrderSend error: ", e);
        }
        else
        {
            if (Execution_Mode == SYMBOL_TRADE_EXECUTION_MARKET)
            {
                RefreshRates();
                if (!OrderSelect(result, SELECT_BY_TICKET))
                {
                    Print("Failed to select an order #", result, " for post-open SL/TP application, error: ", GetLastError());
                    return -1;
                }
                if (StopLoss > 0) SL = OrderOpenPrice() - StopLoss * Poin;
                if (TakeProfit > 0) TP = OrderOpenPrice() + TakeProfit * Poin;
                if ((SL != 0) || (TP != 0))
                {
                    if (!OrderModify(result, OrderOpenPrice(), SL, TP, 0))
                    {
                        Print("Failed to modify an order #", result, " (applying post-open SL/TP), error: ", GetLastError());
                        return -1;
                    }
                }
            }
            return result;
        }
    }
    return -1;
}

void DoTrailing()
{
    int total = OrdersTotal();
    for (int pos = 0; pos < total; pos++)
    {
        if (OrderSelect(pos, SELECT_BY_POS) == false) continue;
        if ((OrderMagicNumber() == Magic) && (OrderSymbol() == Symbol()))
        {
            if (OrderType() == OP_BUY)
            {
                RefreshRates();
                // If profit is greater or equal to the desired Trailing Stop value.
                if (Bid - OrderOpenPrice() >= TrailingStop * Poin)
                {
                    // If the current stop-loss is below the desired trailing stop level.
                    if ((Bid - TrailingStop * Poin) - OrderStopLoss() > Point() / 2) // Double-safe comparison.
                        if (!OrderModify(OrderTicket(), OrderOpenPrice(), Bid - TrailingStop * Poin, OrderTakeProfit(), 0))
                            Print("Failed to modify an order #", OrderTicket(), " (trailing stop), error: ", GetLastError());
                }
            }
            else if (OrderType() == OP_SELL)
            {
                RefreshRates();
                // If profit is greater or equal to the desired Trailing Stop value.
                if (OrderOpenPrice() - Ask >= TrailingStop * Poin)
                {
                    // If the current stop-loss is below the desired trailing stop level.
                    if ((OrderStopLoss() - (Ask + TrailingStop * Poin) > Point() / 2) || (OrderStopLoss() == 0)) // Double-safe comparison.
                        if (!OrderModify(OrderTicket(), OrderOpenPrice(), Ask + TrailingStop * Poin, OrderTakeProfit(), 0))
                            Print("Failed to modify an order #", OrderTicket(), " (trailing stop), error: ", GetLastError());
                }
            }
        }
    }
}

double LotsOptimized()
{
    if (!UseMM) return Lots;
    double vol = NormalizeDouble((AccountFreeMargin() / 10000) * LotsPer10000, 1);
    if (vol <= 0) return Lots;
    return vol;
}

bool CheckTime()
{
    if ((TimeCurrent() >= StringToTime(StartTime)) && (TimeCurrent() <= StringToTime(EndTime) + 59)) // Using +59 seconds to make the minute time inclusive.
    {
        return true;
    }
    return false;
}
//+------------------------------------------------------------------+