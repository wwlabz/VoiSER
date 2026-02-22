import Foundation

public enum WhisperModelOption: String, CaseIterable, Codable, Sendable {
    case small
    case tiny
    case base

    public var title: String {
        switch self {
        case .small:
            "Small (баланс)"
        case .tiny:
            "Tiny (быстрее)"
        case .base:
            "Base (точнее)"
        }
    }

    var folderName: String {
        "openai_whisper-\(rawValue)"
    }
}

public enum HotkeyPreset: String, CaseIterable, Codable, Sendable {
    case optionSpace
    case controlSpace
    case commandShiftSpace
    case optionReturn

    public var title: String {
        switch self {
        case .optionSpace:
            "Option + Space"
        case .controlSpace:
            "Control + Space"
        case .commandShiftSpace:
            "Command + Shift + Space"
        case .optionReturn:
            "Option + Return"
        }
    }
}

public enum SingleKeyOption: Int, CaseIterable, Codable, Sendable {
    case space = 49
    case `return` = 36
    case tab = 48
    case escape = 53
    case delete = 51
    case a = 0
    case b = 11
    case c = 8
    case d = 2
    case e = 14
    case f = 3
    case g = 5
    case h = 4
    case i = 34
    case j = 38
    case k = 40
    case l = 37
    case m = 46
    case n = 45
    case o = 31
    case p = 35
    case q = 12
    case r = 15
    case s = 1
    case t = 17
    case u = 32
    case v = 9
    case w = 13
    case x = 7
    case y = 16
    case z = 6
    case digit0 = 29
    case digit1 = 18
    case digit2 = 19
    case digit3 = 20
    case digit4 = 21
    case digit5 = 23
    case digit6 = 22
    case digit7 = 26
    case digit8 = 28
    case digit9 = 25
    case f1 = 122
    case f2 = 120
    case f3 = 99
    case f4 = 118
    case f5 = 96
    case f6 = 97
    case f7 = 98
    case f8 = 100
    case f9 = 101
    case f10 = 109
    case f11 = 103
    case f12 = 111

    public var title: String {
        switch self {
        case .space: return "Space"
        case .return: return "Return"
        case .tab: return "Tab"
        case .escape: return "Escape"
        case .delete: return "Delete"
        case .a: return "A"
        case .b: return "B"
        case .c: return "C"
        case .d: return "D"
        case .e: return "E"
        case .f: return "F"
        case .g: return "G"
        case .h: return "H"
        case .i: return "I"
        case .j: return "J"
        case .k: return "K"
        case .l: return "L"
        case .m: return "M"
        case .n: return "N"
        case .o: return "O"
        case .p: return "P"
        case .q: return "Q"
        case .r: return "R"
        case .s: return "S"
        case .t: return "T"
        case .u: return "U"
        case .v: return "V"
        case .w: return "W"
        case .x: return "X"
        case .y: return "Y"
        case .z: return "Z"
        case .digit0: return "0"
        case .digit1: return "1"
        case .digit2: return "2"
        case .digit3: return "3"
        case .digit4: return "4"
        case .digit5: return "5"
        case .digit6: return "6"
        case .digit7: return "7"
        case .digit8: return "8"
        case .digit9: return "9"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .f11: return "F11"
        case .f12: return "F12"
        }
    }
}

public enum WidgetStyleOption: String, CaseIterable, Codable, Sendable {
    case micOrb
    case voiceBar
    case pulseDot
    case notchTop

    public var title: String {
        switch self {
        case .micOrb:
            "Mic Orb"
        case .voiceBar:
            "Voice Bar"
        case .pulseDot:
            "Pulse Dot"
        case .notchTop:
            "Notch"
        }
    }

    public var subtitle: String {
        switch self {
        case .micOrb:
            "Классический круглый микрофон"
        case .voiceBar:
            "Полоска уровня голоса"
        case .pulseDot:
            "Компактная пульсирующая кнопка"
        case .notchTop:
            "Скрыт в idle, появляется сверху при записи"
        }
    }

    public var symbolName: String {
        switch self {
        case .micOrb:
            "mic.fill"
        case .voiceBar:
            "waveform.path.ecg"
        case .pulseDot:
            "record.circle.fill"
        case .notchTop:
            "menubar.dock.rectangle"
        }
    }
}

public enum TextOutputMode: String, CaseIterable, Codable, Sendable {
    case clipboard
    case pasteAtCursor
    case pasteStrict

    public var title: String {
        switch self {
        case .clipboard:
            "Копировать в буфер"
        case .pasteAtCursor:
            "Вставлять в активное поле"
        case .pasteStrict:
            "Только вставка (строго)"
        }
    }

    public var subtitle: String {
        switch self {
        case .clipboard:
            "Текст только в буфере обмена"
        case .pasteAtCursor:
            "Если поле ввода активно: вставляет сразу, иначе копирует в буфер"
        case .pasteStrict:
            "Требует активное поле и Accessibility, иначе покажет ошибку"
        }
    }
}

public enum WidgetPresentationMode: String, CaseIterable, Codable, Sendable {
    case overlayOnly
    case menuBarOnly
    case menuBarAndOverlay

    public var title: String {
        switch self {
        case .overlayOnly:
            "Только overlay"
        case .menuBarOnly:
            "Только menu bar"
        case .menuBarAndOverlay:
            "Menu bar + overlay"
        }
    }

    public var subtitle: String {
        switch self {
        case .overlayOnly:
            "Классический плавающий виджет"
        case .menuBarOnly:
            "Виджет только в верхней панели macOS"
        case .menuBarAndOverlay:
            "Верхняя панель + плавающий виджет"
        }
    }
}
