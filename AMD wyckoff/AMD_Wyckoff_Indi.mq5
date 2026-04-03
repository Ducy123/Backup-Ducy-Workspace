//+------------------------------------------------------------------+
//|                                           AMD_Wyckoff_Indi.mq5   |
//|                                                                  |
//+------------------------------------------------------------------+
#property copyright "Your Name"
#property link      ""
#property version   "4.00"
#property indicator_chart_window
#property indicator_buffers 0
#property indicator_plots 0

input group "--- CAI DAT TELEGRAM BOT ---"
input string InpTelegramToken  = ""; 
input string InpTelegramChatID = ""; 
input bool   InpSendAlerts     = true; 

input group "--- BỘ LỌC THỜI GIAN (TIME ZONE) ---"
input int    InpStartHour   = 6;
input int    InpStartMin    = 0;
input int    InpEndHour     = 22;
input int    InpEndMin      = 30;

input group "--- CAI DAT THUẬT TOÁN WYCKOFF ---"
input int    InpAccLength   = 20;  // Độ dài tối thiểu Accumulation (Số nến)
input double InpAccWidthATR = 3.0; // Biên độ đi ngang tối đa (x ATR)
input int    InpMaxManBars  = 8;   // Thời gian Manipulation tối đa (Số nến)
input double InpMaxManDist  = 1.5; // Khoảng quét tối đa (x Chiều cao hộp Acc)
input int    InpDistBoxLen  = 15;  // Chiều dài hộp Distribution vẽ ra (Số nến)

input group "--- HIỆU SUẤT ---"
input int    InpMaxHistory  = 500; // Số nến lịch sử tối đa khi tải lại chart

// State Tracking
int state = 0;
bool can_search = true;
int man_bars = 0;

double acc_top = 0.0;
double acc_bot = 0.0;
datetime acc_start_time = 0;

double man_top = 0.0;
double man_bot = 0.0;
datetime man_start_time = 0;

string curr_acc_name = "";
string curr_man_name = "";
string curr_dist_name = "";

// Cache để tránh gọi ObjectSet không cần thiết
double cached_acc_top = 0.0, cached_acc_bot = 0.0;
datetime cached_acc_t2 = 0;
double cached_man_top = 0.0, cached_man_bot = 0.0;
datetime cached_man_t2 = 0;

datetime last_alert_time = 0;

int atrHandle;
double atrBuffer[];

//+------------------------------------------------------------------+
//| Telegram API                                                     |
//+------------------------------------------------------------------+
void SendTelegramAlert(string symbol, string type)
{
   if(!InpSendAlerts || InpTelegramToken == "" || InpTelegramChatID == "") return;
   
   string time_str = TimeToString(TimeLocal(), TIME_DATE|TIME_MINUTES) + "h GMT+7";
   string message = symbol + " đang xuất hiện manipulation tiềm năng (" + type + ") lúc " + time_str;
   
   string url = "https://api.telegram.org/bot" + InpTelegramToken + "/sendMessage";
   string data = "chat_id=" + InpTelegramChatID + "&text=" + message;
   
   char post[], result[];
   string headers;
   StringToCharArray(data, post, 0, WHOLE_ARRAY, CP_UTF8);
   
   int res = WebRequest("POST", url, "application/x-www-form-urlencoded", 5000, post, result, headers);
   
   if(res != 200)
      Print("Gửi Telegram lỗi: ", res, " -> Nhớ thêm api.telegram.org vào Allowed WebRequest URLs");
}

//+------------------------------------------------------------------+
//| Utilities Vẽ Hộp (Boxes) - Chỉ tạo 1 lần, update khi thay đổi  |
//+------------------------------------------------------------------+
void DrawBox(string name, datetime t1, double p1, datetime t2, double p2, color clr, bool dashed)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FILL, false); 
      ObjectSetInteger(0, name, OBJPROP_BACK, false);
      ObjectSetInteger(0, name, OBJPROP_STYLE, dashed ? STYLE_DASH : STYLE_SOLID); 
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   }
   
   // Chỉ update 4 tọa độ (bỏ qua các property khác đã set)
   ObjectSetInteger(0, name, OBJPROP_TIME,  0, t1);
   ObjectSetDouble(0, name,  OBJPROP_PRICE, 0, p1);
   ObjectSetInteger(0, name, OBJPROP_TIME,  1, t2);
   ObjectSetDouble(0, name,  OBJPROP_PRICE, 1, p2);
}

// Chỉ gọi DrawBox khi có sự thay đổi thực sự - tiết kiệm object API calls
void UpdateAccBox(datetime t2_bar)
{
   if(curr_acc_name == "") return;
   if(cached_acc_top == acc_top && cached_acc_bot == acc_bot && cached_acc_t2 == t2_bar) return;
   DrawBox(curr_acc_name, acc_start_time, acc_top, t2_bar, acc_bot, clrDodgerBlue, false);
   cached_acc_top = acc_top;
   cached_acc_bot = acc_bot;
   cached_acc_t2  = t2_bar;
}

void UpdateManBox(datetime t2_bar)
{
   if(curr_man_name == "") return;
   if(cached_man_top == man_top && cached_man_bot == man_bot && cached_man_t2 == t2_bar) return;
   bool is_up = (StringFind(curr_man_name, "_Up_") >= 0);
   DrawBox(curr_man_name, man_start_time, man_top, t2_bar, man_bot, clrPurple, true);
   cached_man_top = man_top;
   cached_man_bot = man_bot;
   cached_man_t2  = t2_bar;
}

void InvalidateBoxes()
{
   if(curr_acc_name != "") ObjectSetInteger(0, curr_acc_name, OBJPROP_COLOR, clrDimGray);
   if(curr_man_name != "") ObjectSetInteger(0, curr_man_name, OBJPROP_COLOR, clrDimGray);
   curr_acc_name = "";
   curr_man_name = "";
   cached_acc_top = 0; cached_acc_bot = 0; cached_acc_t2 = 0;
   cached_man_top = 0; cached_man_bot = 0; cached_man_t2 = 0;
}

//+------------------------------------------------------------------+
string GetCountdown()
{
   datetime now = TimeCurrent(); 
   MqlDateTime dt;
   TimeToStruct(now, dt);
   
   int current_mins = dt.hour * 60 + dt.min;
   int start_mins = InpStartHour * 60 + InpStartMin;
   int end_mins = InpEndHour * 60 + InpEndMin;
   
   int target_mins = 0;
   string msg_suffix = "";
   
   bool in_zone = false;
   if(start_mins <= end_mins) 
   {
      in_zone = (current_mins >= start_mins && current_mins < end_mins);
      if(in_zone) {
         target_mins = end_mins;
         msg_suffix = "left in Active Zone (Trading)";
      } else {
         target_mins = start_mins;
         if(current_mins >= end_mins) target_mins += 24 * 60;
         msg_suffix = "until Active Zone begins";
      }
   } 
   else 
   {
      in_zone = (current_mins >= start_mins || current_mins < end_mins);
      if(in_zone) {
         target_mins = end_mins;
         if(current_mins >= start_mins) target_mins += 24 * 60;
         msg_suffix = "left in Active Zone (Trading)";
      } else {
         target_mins = start_mins;
         msg_suffix = "until Active Zone begins";
      }
   }
   
   int diff = target_mins - current_mins;
   if(diff < 0) diff = 0;
   int h = diff / 60;
   int m = diff % 60;
   
   string h_str = IntegerToString(h);
   if(h < 10) h_str = "0" + h_str;
   string m_str = IntegerToString(m);
   if(m < 10) m_str = "0" + m_str;
   
   return h_str + ":" + m_str + " " + msg_suffix;
}

//+------------------------------------------------------------------+
//| Dashboard UI                                                     |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, int size, color clr)
{
   if(ObjectFind(0, name) < 0)
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_LOWER);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_RIGHT_LOWER); 
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_FONT, "Segoe UI");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
}

void UpdateDashboard(string session_str, string phase_str, color phase_clr)
{
   CreateLabel("AMD_Dash_Title",   10, 80, "AMD WYCKOFF SYSTEM",        11, clrGold);
   CreateLabel("AMD_Dash_Symbol",  10, 60, "Asset: " + _Symbol,         10, clrWhite);
   CreateLabel("AMD_Dash_Session", 10, 40, "Session: " + session_str,   10, clrLightSkyBlue);
   CreateLabel("AMD_Dash_Phase",   10, 20, "Phase: " + phase_str,       10, phase_clr);
}

//+------------------------------------------------------------------+
int OnInit()
{
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, 14);
   if(atrHandle == INVALID_HANDLE) return INIT_FAILED;
   ArraySetAsSeries(atrBuffer, true);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "Acc_");
   ObjectsDeleteAll(0, "Man_");
   ObjectsDeleteAll(0, "Dist_");
   ObjectsDeleteAll(0, "AMD_Dash_");
   ChartRedraw(0);
}

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   if(rates_total < InpAccLength * 2) return 0;
   
   ArraySetAsSeries(time,  true);
   ArraySetAsSeries(open,  true);
   ArraySetAsSeries(high,  true);
   ArraySetAsSeries(low,   true);
   ArraySetAsSeries(close, true);
   
   // Copy toàn bộ ATR 1 lần duy nhất - tránh gọi lại nhiều lần
   if(CopyBuffer(atrHandle, 0, 0, rates_total, atrBuffer) <= 0) return 0;
   
   int limit = rates_total - prev_calculated;
   
   if(prev_calculated == 0 || limit > 1)
   {
      // === FIX PERFORMANCE: Giới hạn số nến quét lịch sử ===
      // Thay vì quét toàn bộ (có thể hàng chục nghìn nến), chỉ quét InpMaxHistory nến gần nhất
      limit = MathMin(rates_total - InpAccLength - 1, InpMaxHistory);
      state = 0;
      can_search = true;
      cached_acc_top = 0; cached_acc_bot = 0; cached_acc_t2 = 0;
      cached_man_top = 0; cached_man_bot = 0; cached_man_t2 = 0;
      curr_acc_name = "";
      curr_man_name = "";
      curr_dist_name = "";
      ObjectsDeleteAll(0, "Acc_");
      ObjectsDeleteAll(0, "Man_");
      ObjectsDeleteAll(0, "Dist_");
   }

   string current_session = "--";
   string current_phase = "--";
   color phase_clr = clrWhite;

   for(int i = limit; i >= 0; i--) 
   {
      MqlDateTime dt;
      TimeToStruct(time[i], dt);
      int cur_time_mins = dt.hour * 60 + dt.min;
      int start_mins = InpStartHour * 60 + InpStartMin;
      int end_mins   = InpEndHour * 60 + InpEndMin;
      
      bool in_session = false;
      if(start_mins <= end_mins) {
         in_session = (cur_time_mins >= start_mins && cur_time_mins < end_mins);
      } else {
         in_session = (cur_time_mins >= start_mins || cur_time_mins < end_mins);
      }
      
      double atr = atrBuffer[i];
      
      // Tính hh/ll trong cửa sổ InpAccLength nến
      double hh = high[i];
      double ll = low[i];
      int end_k = i + InpAccLength;
      if(end_k >= rates_total) end_k = rates_total - 1;
      for(int k = i + 1; k <= end_k; k++) {
         if(high[k] > hh) hh = high[k];
         if(low[k]  < ll) ll = low[k];
      }
      
      bool is_sideways = ((hh - ll) <= (atr * InpAccWidthATR));

      if(!in_session) 
      {
         if(state != 0) InvalidateBoxes();
         state = 0;
      }
      
      if(state == 0 && !is_sideways)
         can_search = true;
         
      int prev_state = state;

      // ====================== STATE MACHINE ======================
      if(state == 0)
      {
         if(is_sideways && can_search && in_session)
         {
            state = 1;
            acc_top = hh;
            acc_bot = ll;
            
            int start_idx = i + InpAccLength - 1;
            if(start_idx >= rates_total) start_idx = rates_total - 1;
            acc_start_time = time[start_idx];
            can_search = false;
            
            curr_acc_name = "Acc_" + IntegerToString(acc_start_time);
            // Reset cache để force vẽ mới
            cached_acc_top = 0; cached_acc_bot = 0; cached_acc_t2 = 0;
            UpdateAccBox(time[i]);
         }
      }
      else if(state == 1)
      {
         if(close[i] > acc_top)
         {
            state = 2;
            man_start_time = time[i];
            man_bars = 0;
            man_top = high[i];
            man_bot = acc_top;
            
            curr_man_name = "Man_Up_" + IntegerToString(acc_start_time);
            cached_man_top = 0; cached_man_bot = 0; cached_man_t2 = 0;
            // Update acc box đóng lại tại bar này
            UpdateAccBox(time[i]);
            UpdateManBox(time[i]);
         }
         else if(close[i] < acc_bot)
         {
            state = 3;
            man_start_time = time[i];
            man_bars = 0;
            man_bot = low[i];
            man_top = acc_bot;
            
            curr_man_name = "Man_Dn_" + IntegerToString(acc_start_time);
            cached_man_top = 0; cached_man_bot = 0; cached_man_t2 = 0;
            UpdateAccBox(time[i]);
            UpdateManBox(time[i]);
         }
         else
         {
            // Điều chỉnh biên Acc nếu có wick ra ngoài
            bool changed = false;
            if(high[i] > acc_top) { acc_top = high[i]; changed = true; }
            if(low[i]  < acc_bot) { acc_bot = low[i];  changed = true; }
            // UpdateAccBox chỉ vẽ lại khi thực sự thay đổi (nhờ cache check bên trong)
            UpdateAccBox(time[i]);
         }
      }
      else if(state == 2) // Manipulation Up → chờ trigger Dist Down
      {
         man_bars++;
         double acc_height = acc_top - acc_bot;
         bool is_invalid_time = (man_bars > InpMaxManBars);
         bool is_invalid_dist = ((high[i] - acc_top) > (acc_height * InpMaxManDist));
         
         if(is_invalid_time || is_invalid_dist)
         {
            InvalidateBoxes();
            state = 0;
         }
         else if(close[i] <= acc_top) // Trigger setup: giá quay về trong box
         {
            curr_dist_name = "Dist_Dn_" + IntegerToString(time[i]);
            datetime end_time = time[i] + InpDistBoxLen * PeriodSeconds();
            DrawBox(curr_dist_name, time[i], acc_top, end_time, acc_bot, clrRed, false);
            state = 0;
            curr_acc_name = "";
            curr_man_name = "";
         }
         else
         {
            if(high[i] > man_top) man_top = high[i];
            UpdateManBox(time[i]);
         }
      }
      else if(state == 3) // Manipulation Down → chờ trigger Dist Up
      {
         man_bars++;
         double acc_height = acc_top - acc_bot;
         bool is_invalid_time = (man_bars > InpMaxManBars);
         bool is_invalid_dist = ((acc_bot - low[i]) > (acc_height * InpMaxManDist));
         
         if(is_invalid_time || is_invalid_dist)
         {
            InvalidateBoxes();
            state = 0;
         }
         else if(close[i] >= acc_bot) // Trigger setup: giá quay về trong box
         {
            curr_dist_name = "Dist_Up_" + IntegerToString(time[i]);
            datetime end_time = time[i] + InpDistBoxLen * PeriodSeconds();
            DrawBox(curr_dist_name, time[i], acc_top, end_time, acc_bot, clrLimeGreen, false);
            state = 0;
            curr_acc_name = "";
            curr_man_name = "";
         }
         else
         {
            if(low[i] < man_bot) man_bot = low[i];
            UpdateManBox(time[i]);
         }
      }
      
      // Trigger Telegram Alert (chỉ gửi khi live tick)
      if(prev_calculated > 0 && i == 0 && (state == 2 || state == 3) && prev_state == 1)
      {
         if(TimeLocal() - last_alert_time >= 60)
         {
            last_alert_time = TimeLocal();
            string type = (state == 2) ? "Quét Đỉnh - Khả năng Short" : "Quét Đáy - Khả năng Long";
            SendTelegramAlert(_Symbol, type);
         }
      }

      // Update Dashboard (chỉ ở live tick)
      if(i == 0)
      {
         string countdown_str = GetCountdown();

         if(in_session) current_session = "Trading Zone (" + countdown_str + ")";
         else           current_session = "Off Zone (" + countdown_str + ")";

         if(state == 0)      { current_phase = "Sideway (Waiting Pattern)"; phase_clr = clrGray; }
         else if(state == 1) { current_phase = "Forming Accumulation";      phase_clr = clrDodgerBlue; }
         else if(state == 2) { current_phase = "MANIPULATION UP (Sweep High)"; phase_clr = clrMagenta; }
         else if(state == 3) { current_phase = "MANIPULATION DOWN (Sweep Low)"; phase_clr = clrMagenta; }
      }
   }
   
   UpdateDashboard(current_session, current_phase, phase_clr);

   return rates_total;
}
//+------------------------------------------------------------------+
