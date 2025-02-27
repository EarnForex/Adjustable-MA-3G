﻿//+------------------------------------------------------------------+
//|                         Adjustable 3rd Generation Moving Average |
//|                             Copyright © 2011-2025, EarnForex.com |
//|                                       https://www.earnforex.com/ |
//+------------------------------------------------------------------+
#property copyright "Copyright © 2011-2025, EarnForex"
#property link      "https://www.earnforex.com/metatrader-expert-advisors/Adjustable-MA-3G/"
#property version   "1.04"

#property description "Adjustable MA 3G EA - expert advisor for customizable MA trading."
#property description "Uses 3rd Generation Moving Average indicator."
#property description "Modify StopLoss, TakeProfit, TrailingStop, MA Period, MA Type"
#property description "and minimum difference between MAs to count as cross."
#property icon "\\Files\\EF-Icon-64x64px.ico"

#include <Trade/Trade.mqh>

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
input int Period_1     = 35;
input int Period_2     = 30;
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

// Main trading object.
CTrade *Trade;

// These depend on broker's quotes:
double Poin;
ulong Deviation;

int LastBars = 0;

// 0 - undefined, 1 - bullish cross (fast MA above slow MA), -1 - bearish cross (fast MA below slow MA).
int PrevCross = 0;

int Magic; // Will work only in hedging mode.
bool CanTrade = false;

ENUM_SYMBOL_TRADE_EXECUTION Execution_Mode;

int SlowMA, FastMA;
int myFastMA, mySlowMA;

//+------------------------------------------------------------------+
//| Initialization                                                   |
//+------------------------------------------------------------------+
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

    Poin = _Point;
    Deviation = Slippage;
    // Checking for unconventional Point digits number.
    if ((Poin == 0.00001) || (Poin == 0.001))
    {
        Poin *= 10;
        Deviation *= 10;
    }

    myFastMA = iCustom(NULL, 0, "3rdGenMA", FastMA, Period_Sampling_Fast, MA_Method_Fast, MA_Applied_Price_Fast);
    if (myFastMA == INVALID_HANDLE)
    {
        Print("Failed to load custom indicator 3rdGenMA: ", GetLastError());
        return INIT_FAILED;
    }
    mySlowMA = iCustom(NULL, 0, "3rdGenMA", SlowMA, Period_Sampling_Slow, MA_Method_Slow, MA_Applied_Price_Slow);
    if (mySlowMA == INVALID_HANDLE)
    {
        Print("Failed to load custom indicator 3rdGenMA: ", GetLastError());
        return INIT_FAILED;
    }

    Trade = new CTrade;
    Trade.SetDeviationInPoints(Deviation);
    Magic = PeriodSeconds() + 19472394; // Will work only in hedging mode.
    Trade.SetExpertMagicNumber(Magic);

    return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
    delete Trade;
}

void OnTick()
{
    Execution_Mode = (ENUM_SYMBOL_TRADE_EXECUTION)SymbolInfoInteger(Symbol(), SYMBOL_TRADE_EXEMODE);
    if (Execution_Mode == SYMBOL_TRADE_EXECUTION_MARKET) DoSLTP(); // ECN mode - set SL and TP.

    CanTrade = CheckTime();

    if ((TrailingStop > 0) && ((CanTrade) || (DoTrailingOutsideTradingTime))) DoTrailing();

    // Wait for the new Bar in a chart.
    if (LastBars == Bars(_Symbol, _Period)) return;
    else LastBars = Bars(_Symbol, _Period);

    if ((Bars(_Symbol, _Period) < Period_Sampling_Slow) || (TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) == false)) return;

    CheckCross();
}

//+------------------------------------------------------------------+
//| Check for cross and open/close the positions respectively.       |
//+------------------------------------------------------------------+
void CheckCross()
{
    double FMABuffer[], SMABuffer[];

    CopyBuffer(myFastMA, 0, 1, 1, FMABuffer);
    CopyBuffer(mySlowMA, 0, 1, 1, SMABuffer);

    double FMA_Current = FMABuffer[0];
    double SMA_Current = SMABuffer[0];

    if (PrevCross == 0) // Was undefined.
    {
        if ((FMA_Current - SMA_Current) >= MinDiff * Poin) PrevCross = 1; // Bullish state.
        else if ((SMA_Current - FMA_Current) >= MinDiff * Poin) PrevCross = -1; // Bearish state.
        return;
    }
    else if (PrevCross == 1) // Was bullish.
    {
        if ((SMA_Current - FMA_Current) >= MinDiff * Poin) // Became bearish.
        {
            if ((CanTrade) || (CloseTradesOutsideTradingTime)) ClosePrev();
            if ((CanTrade) && (TradeDirection != TRADE_DIRECTION_LONG)) fSell();
            PrevCross = -1;
        }
    }
    else if (PrevCross == -1) // Was bearish.
    {
        if ((FMA_Current - SMA_Current) >= MinDiff * Poin) // Became bullish.
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
    // Closing positions if necessary.
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0)
        {
            int error = GetLastError();
            Print("PositionGetTicket failed " + IntegerToString(error) + ".");
            continue;
        }
        if (PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        if (PositionGetInteger(POSITION_MAGIC) != Magic) continue;
        if (SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
        {
            Print("Trading disabled in symbol: " + PositionGetString(POSITION_SYMBOL) + ".");
            continue;
        }
        for (int j = 0; j < 10; j++)
        {
            if (Trade.PositionClose(ticket)) break;
            else Print("Failed to close position #", ticket, ", error: ", GetLastError());
        }
    }
}

//+------------------------------------------------------------------+
//| Sell                                                             |
//+------------------------------------------------------------------+
void fSell()
{
    double SL, TP;
    if (StopLoss > 0) SL = SymbolInfoDouble(Symbol(), SYMBOL_BID) + StopLoss * Poin;
    else SL = 0;
    if (TakeProfit > 0) TP = SymbolInfoDouble(Symbol(), SYMBOL_BID) - TakeProfit * Poin;
    else TP = 0;

    if (Execution_Mode != SYMBOL_TRADE_EXECUTION_MARKET)
    {
        SL = NormalizeDouble(SL, _Digits);
        TP = NormalizeDouble(TP, _Digits);
    }
    else
    {
        SL = 0;
        TP = 0;
    }

    for (int i = 0; i < 10; i++)
    {
        if (!Trade.Sell(LotsOptimized(), Symbol(), NormalizeDouble(SymbolInfoDouble(Symbol(), SYMBOL_BID), _Digits), SL, TP, OrderCommentary))
        {
            Print("Error sending order: " + Trade.ResultRetcodeDescription() + ".");
        }
        else break;
    }
}

//+------------------------------------------------------------------+
//| Buy                                                              |
//+------------------------------------------------------------------+
void fBuy()
{
    double SL, TP;
    if (StopLoss > 0) SL = SymbolInfoDouble(Symbol(), SYMBOL_ASK) - StopLoss * Poin;
    else SL = 0;
    if (TakeProfit > 0) TP = SymbolInfoDouble(Symbol(), SYMBOL_ASK) + TakeProfit * Poin;
    else TP = 0;

    if (Execution_Mode != SYMBOL_TRADE_EXECUTION_MARKET)
    {
        SL = NormalizeDouble(SL, _Digits);
        TP = NormalizeDouble(TP, _Digits);
    }
    else
    {
        SL = 0;
        TP = 0;
    }

    for (int i = 0; i < 10; i++)
    {
        if (!Trade.Buy(LotsOptimized(), Symbol(), NormalizeDouble(SymbolInfoDouble(Symbol(), SYMBOL_ASK), _Digits), SL, TP, OrderCommentary))
        {
            Print("Error sending order: " + Trade.ResultRetcodeDescription() + ".");
        }
        else break;
    }
}

void DoTrailing()
{
    // Modifying SL if necessary.
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0)
        {
            int error = GetLastError();
            Print("PositionGetTicket failed " + IntegerToString(error) + ".");
            continue;
        }
        if (PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        if (PositionGetInteger(POSITION_MAGIC) != Magic) continue;
        if (SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
        {
            Print("Trading disabled in symbol: " + PositionGetString(POSITION_SYMBOL) + ".");
            continue;
        }

        // If the open position is Long.
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            // If profit is greater or equal to the desired Trailing Stop value.
            if (SymbolInfoDouble(Symbol(), SYMBOL_BID) - PositionGetDouble(POSITION_PRICE_OPEN) >= TrailingStop * Poin)
            {
                if ((SymbolInfoDouble(Symbol(), SYMBOL_BID) - TrailingStop * Poin) - PositionGetDouble(POSITION_SL) > Point() / 2) // Double-safe comparison.
                {
                    double SL = NormalizeDouble(SymbolInfoDouble(Symbol(), SYMBOL_BID) - TrailingStop * Poin, _Digits);
                    double TP = PositionGetDouble(POSITION_TP);
                    Trade.PositionModify(ticket, SL, TP);
                }
            }
        }
        // If it is Short.
        else
        {
            // If profit is greater or equal to the desired Trailing Stop value.
            if (PositionGetDouble(POSITION_PRICE_OPEN) - SymbolInfoDouble(Symbol(), SYMBOL_ASK) >= TrailingStop * Poin)
            {
                if ((PositionGetDouble(POSITION_SL) - (SymbolInfoDouble(Symbol(), SYMBOL_ASK) + TrailingStop * Poin) > Point() / 2) || (PositionGetDouble(POSITION_SL) == 0)) // Double-safe comparison.
                {
                    double SL = NormalizeDouble(SymbolInfoDouble(Symbol(), SYMBOL_ASK) + TrailingStop * Poin, _Digits);
                    double TP = PositionGetDouble(POSITION_TP);
                    Trade.PositionModify(ticket, SL, TP);
                }
            }
        }
    }
}

double LotsOptimized()
{
    if (!UseMM) return Lots;
    double vol = NormalizeDouble((AccountInfoDouble(ACCOUNT_MARGIN_FREE) / 10000) * LotsPer10000, 1);
    if (vol <= 0) return 0.1;
    return(vol);
}

//+------------------------------------------------------------------+
//| Applies SL and TP to open positions if ECN mode is on.           |
//+------------------------------------------------------------------+
void DoSLTP()
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket <= 0)
        {
            int error = GetLastError();
            Print("PositionGetTicket failed " + IntegerToString(error) + ".");
            continue;
        }
        if (PositionGetString(POSITION_SYMBOL) != Symbol()) continue;
        if (PositionGetInteger(POSITION_MAGIC) != Magic) continue;
        if (SymbolInfoInteger(PositionGetString(POSITION_SYMBOL), SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
        {
            Print("Trading disabled in symbol: " + PositionGetString(POSITION_SYMBOL) + ".");
            continue;
        }

        double SL = 0, TP = 0;

        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
        {
            if (StopLoss > 0) SL = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN) - StopLoss * Poin, _Digits);
            if (TakeProfit > 0) TP = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN) + TakeProfit * Poin, _Digits);
        }
        if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
        {
            if (StopLoss > 0) SL = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN) + StopLoss * Poin, _Digits);
            if (TakeProfit > 0) TP = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN) - TakeProfit * Poin, _Digits);
        }

        if (((PositionGetDouble(POSITION_SL) != SL) || (PositionGetDouble(POSITION_TP) != TP)) && (PositionGetDouble(POSITION_SL) == 0) && (PositionGetDouble(POSITION_TP) == 0))
        {
            Trade.PositionModify(_Symbol, SL, TP);
        }
    }
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