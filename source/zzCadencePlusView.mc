import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

typedef Font as WatchUi.FontResource or Graphics.FontDefinition;

// zzCadencePlus
//  - 10필드 칸(반폭): 위쪽 줄 = 케이던스 아이콘 + 보조 값 + rpm / 아래쪽 줄 = 현재 케이던스 + rpm
//  - 넓은 칸(전체폭): 위쪽 = 아이콘 + "zzCadencePlus" + 모드/단위 / 아래 = 두 값 같은 크기로 나란히
//  - 현재 케이던스 색상: 기준보다 5% 넘게 높으면 '높을 때 색', 낮으면 '낮을 때 색' (주간/야간 따로)
//  - 글자 크기는 zzSpeedPlus와 동일
// 배터리: 판단·좌표·폰트는 onLayout에서 한 번, compute는 값이 바뀔 때만 문자열 생성, onUpdate는 그리기만.
// APP_VERSION 1.0.1
class zzCadencePlusView extends WatchUi.DataField {

    enum { MODE_CAD, MODE_AVG, MODE_MAX, MODE_LAP }
    private const MODE_LABELS = ["", "AVG", "MAX", "LAP"];

    // 색상표 (설정 값 = 인덱스, 배포 후 순서 변경 금지). 0 = 기본 글자색(색 없음)
    private const COLORS = [0, 0xFF0000, 0xFF55AA, 0xFF00FF, 0xFF5500, 0xFFAA00, 0x00AA00, 0x00AAFF, 0x0000FF, 0xAA00FF];

    // ---- 설정 ----
    private var _mode as Number = MODE_AVG;
    private var _label as String = "";
    private var _dayHigh as Number = 0xFF0000, _dayLow as Number = 0x0000FF;
    private var _nightHigh as Number = 0xFF55AA, _nightLow as Number = 0x00AAFF;
    private var _colorOn as Boolean = true;
    enum { STATE_NORMAL, STATE_HIGH, STATE_LOW }
    // 배경색 : 0 기기 화면색에 맞춤 (1050/1060 은 #17181D / #DCDCDC)
    //          1 기기가 알려준 검정·흰색 그대로 (기본, 지금까지의 동작)
    //          2 투명 - 칠하지 않아 기기 배경이 그대로 비친다
    enum { BG_AUTO, BG_PLAIN, BG_CLEAR }
    private var _bgMode as Number = BG_PLAIN;
    private var _state as Number = STATE_NORMAL;

    // ---- 레이아웃 ----
    private var _wide as Boolean = false;
    private var _titleOn as Boolean = true;
    private var _L as Number = 0, _T as Number = 0, _R as Number = 0, _B as Number = 0;
    // 아이콘('@')은 숫자보다 커서 글자 줄 가운데에 맞춰 위로 올려 그림 (화면 위로는 안 나가게)
    private var _yIconSub as Number = 0, _yIconTitle as Number = 0;

    private var _fMain as Font = Graphics.FONT_XTINY, _fSub as Font = Graphics.FONT_XTINY;
    private var _fUnitMain as Font = Graphics.FONT_XTINY, _fUnitSub as Font = Graphics.FONT_XTINY;
    private var _fVal as Font = Graphics.FONT_XTINY, _fTitle as Font = Graphics.FONT_XTINY, _fLabel as Font = Graphics.FONT_XTINY;
    private var _c10Loaded as Boolean = false;

    // 10필드 칸
    private var _xMainVal as Number = 0, _yMain as Number = 0, _yUnitMain2 as Number = 0;
    private var _xSubVal as Number = 0, _yUnitSub2 as Number = 0;
    // 넓은 칸
    private var _xTitleText as Number = 0, _yLabel as Number = 0;
    private var _title as String = "zzCadencePlus";
    private var _yVal as Number = 0, _xc1 as Number = 0, _xc2 as Number = 0, _xcMid as Number = 0, _yDiv1 as Number = 0;

    // ---- 값 캐시 (rpm 정수, -1 = 없음, -2 = 다시 만들기) ----
    private var _main as Number = -2, _sub as Number = -2;
    private var _mainS as String = "--", _subS as String = "--";

    // ---- Lap 평균 (0 rpm 제외, 타이머 동작 중에만) ----
    private var _lapSum as Number = 0, _lapCnt as Number = 0;

    function initialize() {
        DataField.initialize();
        // 업데이트 후에도 설정 화면에 현재 버전이 보이도록 덮어씀
        Application.Properties.setValue("appVersion", "1.0.2");
        readSettings();
    }

    // App.onSettingsChanged()에서 호출 → WatchUi.requestUpdate()
    function readSettings() as Void {
        // 배경색 : 0 기기 화면색에 맞춤, 1 검정·흰색 그대로(기본), 2 투명
        var bm = Application.Properties.getValue("bgMode");
        _bgMode = (bm instanceof Number && bm >= 0 && bm <= 2) ? bm as Number : BG_PLAIN;

        var m = Application.Properties.getValue("mode");
        _mode = (m instanceof Number && m >= 0 && m <= 3) ? m : MODE_AVG;
        _label = (_mode == MODE_CAD) ? "rpm" : (MODE_LABELS[_mode] + "  rpm");
        _dayHigh   = colorAt(Application.Properties.getValue("dayHighColor"), 1);
        _dayLow    = colorAt(Application.Properties.getValue("dayLowColor"), 8);
        _nightHigh = colorAt(Application.Properties.getValue("nightHighColor"), 2);
        _nightLow  = colorAt(Application.Properties.getValue("nightLowColor"), 7);
        _colorOn = (_dayHigh != 0 || _dayLow != 0 || _nightHigh != 0 || _nightLow != 0);
        _state = STATE_NORMAL;
        _main = -2; _sub = -2;
    }

    private function colorAt(v as Application.Properties.ValueType or Null, def as Number) as Number {
        var i = (v instanceof Number && v >= 0 && v < COLORS.size()) ? v : def;
        return COLORS[i] as Number;
    }

    // =========================================================
    // 레이아웃
    // =========================================================
    function onLayout(dc as Graphics.Dc) as Void {
        var w = dc.getWidth(), h = dc.getHeight();
        _wide = w > System.getDeviceSettings().screenWidth * 0.75f;
        _L = (w * 0.05f + 0.5f).toNumber();
        _T = (h * 0.05f + 0.5f).toNumber();
        _R = w - _L;
        _B = h - _T;
        if (_wide) { layoutWide(dc, w, h); } else { layoutCell10(dc, w); }
    }

    private function layoutCell10(dc as Graphics.Dc, w as Number) as Void {
        _fVal = Graphics.FONT_XTINY; _fTitle = Graphics.FONT_XTINY; _fLabel = Graphics.FONT_XTINY;
        if (!_c10Loaded) {
            _fMain     = WatchUi.loadResource(Rez.Fonts.C10Main) as WatchUi.FontResource;
            _fSub      = WatchUi.loadResource(Rez.Fonts.C10Sub) as WatchUi.FontResource;
            _fUnitMain = WatchUi.loadResource(Rez.Fonts.C10UnitMain) as WatchUi.FontResource;
            _fUnitSub  = WatchUi.loadResource(Rez.Fonts.C10UnitSub) as WatchUi.FontResource;
            _c10Loaded = true;
        }
        var ug = (w * 0.02f).toNumber(); if (ug < 2) { ug = 2; }
        _yMain      = _B - Graphics.getFontAscent(_fMain);
        // 2단 단위: 위 줄은 숫자 윗선, 아래 줄은 위 줄 바로 아래 (p 꼬리 + 약간 띄움). 숫자 바닥선은 넘지 않음
        var aUnit = Graphics.getFontAscent(_fUnitMain);
        _yUnitMain2 = _yMain + (aUnit * 1.45f + 0.5f).toNumber();
        if (_yUnitMain2 > _B - aUnit) { _yUnitMain2 = _B - aUnit; }
        _xMainVal   = _R - unitWidth(dc, _fUnitMain) - ug;
        _yUnitSub2  = _T + Graphics.getFontAscent(_fSub) - Graphics.getFontAscent(_fUnitSub);
        _xSubVal    = _R - unitWidth(dc, _fUnitSub) - ug;
        _yIconSub   = iconTop(_fSub);
    }

    // 아이콘 글리프 높이 = 폰트 lineHeight (아이콘이 가장 큼). 숫자 높이(ascent) 기준 세로 가운데.
    private function iconTop(f as Font) as Number {
        var y = _T + (Graphics.getFontAscent(f) - Graphics.getFontHeight(f)) / 2;
        return (y < 0) ? 0 : y;
    }

    private function layoutWide(dc as Graphics.Dc, w as Number, h as Number) as Void {
        _fSub = Graphics.FONT_XTINY; _fUnitMain = Graphics.FONT_XTINY; _fUnitSub = Graphics.FONT_XTINY;
        _c10Loaded = false;
        _fTitle = WatchUi.loadResource(Rez.Fonts.WideTitle) as WatchUi.FontResource;
        _fLabel = WatchUi.loadResource(Rez.Fonts.WideLabel) as WatchUi.FontResource;
        var fv  = WatchUi.loadResource(Rez.Fonts.WideVal) as WatchUi.FontResource;

        var gap = (w * 0.04f).toNumber(); if (gap < 4) { gap = 4; }
        var vg  = (h * 0.05f).toNumber(); if (vg < 2) { vg = 2; }
        var aTitle = Graphics.getFontAscent(_fTitle);
        _yIconTitle = iconTop(_fTitle);
        var hTitle = _yIconTitle + Graphics.getFontHeight(_fTitle) - _T;   // 아이콘 아래 끝까지
        var hDesc  = (aTitle * 1.3f).toNumber();                              // 'p' 꼬리
        if (hTitle < hDesc) { hTitle = hDesc; }
        var hu = _B - _T;

        _title = (w < 300) ? "zzCadence+" : "zzCadencePlus";   // 좁은 넓은 칸(540/840, 1040)은 짧은 이름
        _titleOn = (hu - hTitle - vg) >= Graphics.getFontAscent(fv);
        if (_titleOn) {
            _fVal = fv; _fMain = Graphics.FONT_XTINY;
        } else {
            // 낮은 칸 (예: 550/850의 420×60): 타이틀 빼고 숫자만
            _fTitle = Graphics.FONT_XTINY; _fLabel = Graphics.FONT_XTINY;
            if (Graphics.getFontAscent(fv) <= hu) { _fVal = fv; _fMain = Graphics.FONT_XTINY; }
            else { _fMain = WatchUi.loadResource(Rez.Fonts.C10Main) as WatchUi.FontResource; _fVal = _fMain; }
        }

        var top = _T;
        if (_titleOn) {
            _xTitleText = _L + dc.getTextWidthInPixels("@", _fTitle);
            _yLabel = _T + aTitle - Graphics.getFontAscent(_fLabel);
            top = _T + hTitle + vg;
        }
        _yVal  = top + (_B - top - Graphics.getFontAscent(_fVal)) / 2;
        _yDiv1 = top;
        var mid = w / 2;
        _xc1   = (_L + mid - gap / 2) / 2;
        _xc2   = (mid + gap / 2 + _R) / 2;
        _xcMid = mid;
    }

    private function unitWidth(dc as Graphics.Dc, f as Font) as Number {
        var a = dc.getTextWidthInPixels("rp", f), c = dc.getTextWidthInPixels("m", f);
        return (a > c) ? a : c;
    }

    // =========================================================
    // 계산
    // =========================================================
    function onTimerLap() as Void   { _lapSum = 0; _lapCnt = 0; }
    function onTimerReset() as Void { _lapSum = 0; _lapCnt = 0; }

    function compute(info as Activity.Info) as Void {
        var cur = info.currentCadence;

        // Lap 평균 누적: 타이머 동작 중, 0 rpm(코스팅) 제외
        if (cur != null && cur > 0 && info.timerState == Activity.TIMER_STATE_ON) {
            _lapSum += cur; _lapCnt += 1;
        }

        var v = (cur == null) ? -1 : cur;
        if (v != _main) { _main = v; _mainS = (v < 0) ? "--" : v.toString(); }

        var avg = info.averageCadence;
        var s = null as Number?;
        if (_mode == MODE_AVG)      { s = avg; }
        else if (_mode == MODE_MAX) { s = info.maxCadence; }
        else if (_mode == MODE_LAP) { s = (_lapCnt > 0) ? ((_lapSum + _lapCnt / 2) / _lapCnt) : null; }

        if (_mode != MODE_CAD) {
            v = (s == null) ? -1 : s;
            if (v != _sub) { _sub = v; _subS = (v < 0) ? "--" : v.toString(); }
        }

        // 색상: 기준 대비 ±5% 초과일 때만 (정수 비교)
        if (_colorOn) {
            var ref = (_mode == MODE_AVG || _mode == MODE_LAP) ? _sub : ((avg == null) ? -1 : avg);
            if (ref <= 0 || _main < 0)            { _state = STATE_NORMAL; }
            else if (_main * 100 > ref * 105)     { _state = STATE_HIGH; }
            else if (_main * 100 < ref * 95)      { _state = STATE_LOW; }
            else                                  { _state = STATE_NORMAL; }
        }
    }

    // =========================================================
    // 그리기
    // =========================================================
    function onUpdate(dc as Graphics.Dc) as Void {
        var sys = getBackgroundColor();
        var sysClear = (sys == Graphics.COLOR_TRANSPARENT);   // 기기가 "투명"이라고 알려준 경우
        var night = (sys == Graphics.COLOR_BLACK || sysClear);
        var soft = (_bgMode == BG_AUTO)
                && (System.getDeviceSettings().screenWidth >= 480);   // 1050 / 1060
        var fg = night ? Graphics.COLOR_WHITE
                       : (soft ? 0x313152 : Graphics.COLOR_BLACK);
        var bg = night ? (soft ? 0x17181D : Graphics.COLOR_BLACK)
                       : (soft ? 0xDCDCDC : Graphics.COLOR_WHITE);
        // 투명 : 칠하지 않아 기기 배경이 그대로 비친다 (테마가 무엇이든 일치)
        if (_bgMode == BG_CLEAR || (_bgMode == BG_AUTO && sysClear)) {
            bg = Graphics.COLOR_TRANSPARENT;
        }
        dc.setColor(fg, bg);
        dc.clear();
        if (dc has :setAntiAlias) { dc.setAntiAlias(true); }
        var mc = 0;
        if (_state == STATE_HIGH)     { mc = night ? _nightHigh : _dayHigh; }
        else if (_state == STATE_LOW) { mc = night ? _nightLow : _dayLow; }
        if (mc == 0) { mc = fg; }
        if (_wide) { drawWide(dc, fg, mc); } else { drawCell10(dc, fg, mc); }
    }

    private function drawCell10(dc as Graphics.Dc, fg as Number, mc as Number) as Void {
        dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_L, _yIconSub, _fSub, "@", Graphics.TEXT_JUSTIFY_LEFT);

        dc.setColor(mc, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_xMainVal, _yMain, _fMain, _mainS, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_R, _yMain,      _fUnitMain, "rp", Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(_R, _yUnitMain2, _fUnitMain, "m",  Graphics.TEXT_JUSTIFY_RIGHT);

        if (_mode == MODE_CAD) { return; }
        dc.drawText(_xSubVal, _T, _fSub, _subS, Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(_R, _T,         _fUnitSub, "rp", Graphics.TEXT_JUSTIFY_RIGHT);
        dc.drawText(_R, _yUnitSub2, _fUnitSub, "m",  Graphics.TEXT_JUSTIFY_RIGHT);
    }

    private function drawWide(dc as Graphics.Dc, fg as Number, mc as Number) as Void {
        if (_titleOn) {
            dc.setColor(Graphics.COLOR_BLUE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_L, _yIconTitle, _fTitle, "@", Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_xTitleText, _T, _fTitle, _title, Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(Graphics.COLOR_DK_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(_R, _yLabel, _fLabel, _label, Graphics.TEXT_JUSTIFY_RIGHT);
        }
        dc.setColor(mc, Graphics.COLOR_TRANSPARENT);
        if (_mode == MODE_CAD) {
            dc.drawText(_xcMid, _yVal, _fVal, _mainS, Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        dc.drawText(_xc1, _yVal, _fVal, _mainS, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(fg, Graphics.COLOR_TRANSPARENT);
        dc.drawText(_xc2, _yVal, _fVal, _subS, Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(_xcMid, _yDiv1, _xcMid, _B);
    }
}
