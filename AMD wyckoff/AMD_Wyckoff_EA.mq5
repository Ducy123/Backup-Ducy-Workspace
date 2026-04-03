//+------------------------------------------------------------------+
//|                                             AMD_Wyckoff_EA.mq5   |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      ""
#property version   "4.10"

#include <Trade\Trade.mqh>
CTrade trade;

enum ENUM_RISK_TYPE {
   RISK_PERCENT = 0, // Tính theo % Tài khoản (Tự động canh R:R)
   RISK_MONEY = 1,   // Cố định số Tiền USD Loss
   RISK_FIXED = 2    // Lot cố định (Đánh ngẫu nhiên)
};

input group "--- QUẢN LÝ VỐN CHUYÊN NGHIỆP ---"
input ENUM_RISK_TYPE InpRiskType  = RISK_PERCENT; // Phương thức rải vốn
input double         InpRiskValue = 1.0;          // Giá trị (VD: 1.0 = 1%, hoặc 100 = 100$, hoặc 0.5 = 0.5 Lot)

input group "--- CÀI ĐẶT CHUNG TỪ HỆ THỐNG ---"
input int    InpMagicNumber  = 12345;               // Magic Number
input string InpIndiName     = "AMD_Wyckoff_Indi";  // Tên Indi bắt đối tượng
input bool   InpAutoAttach   = true;                // Kích hoạt vẽ hiển thị trong Tester
input int    InpMaxSetupAge  = 15;                  // Tuổi thọ Limit (phút) - Expire theo thời gian

int indiHandle = INVALID_HANDLE;

int OnInit()
{
   trade.SetExpertMagicNumber(InpMagicNumber);
   
   if(InpAutoAttach)
   {
      indiHandle = iCustom(_Symbol, PERIOD_CURRENT, InpIndiName);
      if(indiHandle != INVALID_HANDLE)
         ChartIndicatorAdd(0, 0, indiHandle);
      else
         Print("Không bốc được file Indicator ", InpIndiName);
   }
   
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   if(indiHandle != INVALID_HANDLE) IndicatorRelease(indiHandle);
}

double CalculateVolume(double entry_price, double sl_price)
{
   // Trả về số Lot tay lập tức nếu User chọn đánh Lot cứng
   if(InpRiskType == RISK_FIXED)
      return InpRiskValue;
      
   double risk_amount = 0.0;
   
   if(InpRiskType == RISK_PERCENT)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      risk_amount = balance * (InpRiskValue / 100.0);
   }
   else if(InpRiskType == RISK_MONEY)
   {
      risk_amount = InpRiskValue; 
   }
   
   double tick_size  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tick_value = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double min_vol    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_vol    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step       = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   
   if(tick_size == 0 || tick_value == 0 || sl_price == entry_price || step == 0) return min_vol; 
   
   double ticks_dist  = MathAbs(entry_price - sl_price) / tick_size;
   double loss_per_lot = ticks_dist * tick_value;
   
   if(loss_per_lot == 0) return min_vol;
   
   double raw_volume = risk_amount / loss_per_lot;
   
   int vol_digits = 2;
   if(step == 1.0)       vol_digits = 0;
   else if(step == 0.1)  vol_digits = 1;
   else if(step == 0.01) vol_digits = 2;
   else if(step == 0.001) vol_digits = 3;
   else if(step == 0.0001) vol_digits = 4;
   else if(step == 0.00001) vol_digits = 5;
   
   double final_volume = NormalizeDouble(MathFloor(raw_volume / step) * step, vol_digits);
   
   if(final_volume < min_vol) final_volume = min_vol;
   if(final_volume > max_vol) final_volume = max_vol;
   
   return final_volume;
}

// Xóa tất cả pending orders của EA còn chưa fill
void CancelAllPendingOrders()
{
   for(int i = OrdersTotal() - 1; i >= 0; i--)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      if(OrderGetInteger(ORDER_MAGIC) != InpMagicNumber) continue;
      if(OrderGetString(ORDER_SYMBOL) != _Symbol) continue;
      trade.OrderDelete(ticket);
   }
}

void OnTick()
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   int total = ObjectsTotal(0, 0, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string objName = ObjectName(0, i, 0, -1);
      
      // ============================================================
      // === SCAN BÊN BUY ===
      // ============================================================
      if(StringFind(objName, "AMD_Entry_Buy_") == 0)
      {
         // Bỏ qua nếu đã bị vô hiệu hóa
         if((color)ObjectGetInteger(0, objName, OBJPROP_COLOR) == clrDimGray) continue;
         
         string timeSuffix = StringSubstr(objName, 14); 
         datetime objTime  = (datetime)StringToInteger(timeSuffix);
         
         string slName = "AMD_SL_Buy_"  + timeSuffix;
         string tpName = "AMD_TP_Buy_"  + timeSuffix;
         
         if(ObjectFind(0, slName) < 0 || ObjectFind(0, tpName) < 0) continue;
         
         double entryPrice = ObjectGetDouble(0, objName, OBJPROP_PRICE, 0);
         double slPrice    = ObjectGetDouble(0, slName,  OBJPROP_PRICE, 0);
         double tpPrice    = ObjectGetDouble(0, tpName,  OBJPROP_PRICE, 0);
         
         // --- EXPIRE 1: Quá thời gian cho phép ---
         if(TimeCurrent() - objTime > InpMaxSetupAge * 60)
         {
            Print("⏰ EXPIRE BUY (timeout): Setup quá ", InpMaxSetupAge, " phút - bỏ qua");
            ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDimGray);
            CancelAllPendingOrders();
            continue;
         }
         
         // --- EXPIRE 2: Giá đã chạm TP trước khi vào lệnh ---
         // Buy Long: TP ở trên (tpPrice > entryPrice). Nếu Ask đã >= TP → giá đã TP rồi → expire
         if(ask >= tpPrice)
         {
            Print("🚫 EXPIRE BUY (TP hit before fill): Giá Ask=", ask, " đã vượt TP=", tpPrice, " → Setup hết hạn");
            ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDimGray);
            CancelAllPendingOrders();
            continue;
         }
         
         // --- ĐẶT LỆNH: Chỉ đặt nếu entry < ask (Buy Limit hợp lệ) ---
         if(entryPrice < ask)
         {
            double calculated_vol = CalculateVolume(entryPrice, slPrice);
            if(trade.BuyLimit(calculated_vol, entryPrice, _Symbol, slPrice, tpPrice, ORDER_TIME_GTC, 0, "AMD Long Cân Lệnh"))
            {
               Print("⚡ FIRE BUY LIMIT: Lót ", calculated_vol, " Entry=", entryPrice, " SL=", slPrice, " TP=", tpPrice);
               ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDimGray);
            }
         }
      }
      
      // ============================================================
      // === SCAN BÊN SELL ===
      // ============================================================
      else if(StringFind(objName, "AMD_Entry_Sell_") == 0)
      {
         // Bỏ qua nếu đã bị vô hiệu hóa
         if((color)ObjectGetInteger(0, objName, OBJPROP_COLOR) == clrDimGray) continue;
         
         string timeSuffix = StringSubstr(objName, 15); 
         datetime objTime  = (datetime)StringToInteger(timeSuffix);
         
         string slName = "AMD_SL_Sell_"  + timeSuffix;
         string tpName = "AMD_TP_Sell_"  + timeSuffix;
         
         if(ObjectFind(0, slName) < 0 || ObjectFind(0, tpName) < 0) continue;
         
         double entryPrice = ObjectGetDouble(0, objName, OBJPROP_PRICE, 0);
         double slPrice    = ObjectGetDouble(0, slName,  OBJPROP_PRICE, 0);
         double tpPrice    = ObjectGetDouble(0, tpName,  OBJPROP_PRICE, 0);
         
         // --- EXPIRE 1: Quá thời gian cho phép ---
         if(TimeCurrent() - objTime > InpMaxSetupAge * 60)
         {
            Print("⏰ EXPIRE SELL (timeout): Setup quá ", InpMaxSetupAge, " phút - bỏ qua");
            ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDimGray);
            CancelAllPendingOrders();
            continue;
         }
         
         // --- EXPIRE 2: Giá đã chạm TP trước khi vào lệnh ---
         // Sell Short: TP ở dưới (tpPrice < entryPrice). Nếu Bid đã <= TP → giá đã TP rồi → expire
         if(bid <= tpPrice)
         {
            Print("🚫 EXPIRE SELL (TP hit before fill): Giá Bid=", bid, " đã xuống TP=", tpPrice, " → Setup hết hạn");
            ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDimGray);
            CancelAllPendingOrders();
            continue;
         }
         
         // --- ĐẶT LỆNH: Chỉ đặt nếu entry > bid (Sell Limit hợp lệ) ---
         if(entryPrice > bid)
         {
            double calculated_vol = CalculateVolume(entryPrice, slPrice);
            if(trade.SellLimit(calculated_vol, entryPrice, _Symbol, slPrice, tpPrice, ORDER_TIME_GTC, 0, "AMD Short Cân Lệnh"))
            {
               Print("⚡ FIRE SELL LIMIT: Lót ", calculated_vol, " Entry=", entryPrice, " SL=", slPrice, " TP=", tpPrice);
               ObjectSetInteger(0, objName, OBJPROP_COLOR, clrDimGray);
            }
         }
      }
   }
}
//+------------------------------------------------------------------+
