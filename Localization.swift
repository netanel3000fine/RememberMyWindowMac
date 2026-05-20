import Foundation
import SwiftUI

// MARK: - Localization helper
// Bi-directional localization helper. 
// Takes the language explicitly to ensure SwiftUI re-renders when it changes.

extension String {
    func localized(_ lang: AppLanguage) -> String {
        let isHebrew: Bool
        switch lang {
        case .hebrew:  isHebrew = true
        case .english: isHebrew = false
        case .auto:    isHebrew = Locale.current.language.languageCode?.identifier == "he"
        }
        
        if isHebrew {
            return translationDict[self] ?? self
        } else {
            return reverseDict[self] ?? self
        }
    }
}

// Global helper that reads from UserDefaults (for non-View contexts)
func lz(_ key: String) -> String {
    let langStr = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
    let lang = AppLanguage(rawValue: langStr) ?? .auto
    return key.localized(lang)
}

/// Always returns the English/Stable version of a name, used for generating stable keys.
func normalizeToEnglish(_ name: String) -> String {
    // If it's a Hebrew name in our reverse dict, map it back to English.
    // Also handle prefixes like 'צג Retina מובנה'.
    var target = name
    if target.contains("מובנה") {
        return "Built-in Retina Display"
    }
    return reverseDict[target] ?? target
}

private let translationDict: [String: String] = [
    // Onboarding
    "Your window manager": "מנהל החלונות שלך",
    "Choose Your Language": "בחר שפה",
    "Continue": "המשך",
    "Next": "הבא",
    "Get Started": "בואו נתחיל",
    "Remember Every Window": "זכור כל חלון",
    "Save your window layout with one click and restore it in seconds.": "שמור את סידור החלונות שלך בלחיצה אחת ושחזר אותו תוך שניות.",
    "Live Layout Preview": "תצוגה מקדימה חיה",
    "See a real-time minimap of every open window across all your screens.": "ראה מפה חיה של כל חלון פתוח על פני כל המסכים שלך.",
    "Automatic Restoration": "שחזור אוטומטי",
    "Reconnect a monitor or open an app — your layout snaps back instantly.": "חבר מסך או פתח יישום — הסידור חוזר מיידית.",
    "Make It Yours": "התאם אישית",
    "Choose a theme colour, language, and Liquid Glass interface — all in Settings.": "בחר צבע ערכת נושא, שפה וממשק Liquid Glass — הכל בהגדרות.",
    "Saved": "נשמר",
    "Restored": "שוחזר",
    "Settings": "הגדרות",
    "Skip for now": "דלג לעת עתה",
    // Automation
    "Automation": "אוטומציה",
    "Auto-restore on connect": "שחזר אוטומטית בעת חיבור",
    "Restores layout when displays reconnect": "משחזר סידור חלונות כאשר מסכים מתחברים",
    "Auto-restore on app open": "שחזר אוטומטית בפתיחת יישום",
    "Restores layout when an app is launched": "משחזר סידור חלונות עם פתיחת יישום",
    "Animate restoration": "הנפש שחזור",
    "Smoothly move windows to their spots": "הזז חלונות בצורה חלקה למקומם",
    "Launch at login": "הפעל בעת כניסה",
    "Start RememberMyWindows automatically": "הפעל את RememberMyWindows אוטומטית",
    "Activity Log Level": "רמת פירוט לוג",
    "Filter which events appear in the log": "סנן אילו אירועים יופיעו בלוג",
    // Experimental
    "Experimental": "ניסיוני",
    "Desktop Toggle (Cmd+D)": "הצג/הסתר שולחן עבודה (Cmd+D)",
    "Quickly hide/show all windows (disabled for Safari)": "הסתר/הצג במהירות את כל החלונות (מושבת עבור Safari)",
    "Restore on Cmd+D unhide": "שחזר בעת ביטול הסתרה עם Cmd+D",
    "Automatically run layout restore when showing windows": "הפעל שחזור אוטומטי של חלונות בעת חזרתם",
    "Focus configured app on unhide": "התמקדות ביישום שהוגדר בעת ביטול הסתרה",
    "Bring the snapshot's frontmost app to focus when unhiding": "הבא לקדמת הבמה את היישום הראשי של הסידור בעת ביטול הסתרה",
    // Appearance
    "Appearance": "מראה",
    "Liquid Glass interface": "ממשק Liquid Glass",
    "Enable premium transparency and effects": "הפעל שקיפות ואפקטים מתקדמים",
    "Notch Notification": "התראות מגרעת",
    "Show layout restore alerts from the notch": "הצג התראות שחזור מהמגרעת",
    "Theme Color": "צבע ערכת נושא",
    "Primary accent for the interface": "צבע הדגשה ראשי לממשק",
    "App Language": "שפת היישום",
    "Override the system language": "עקוף את שפת המערכת",
    "Restart app to apply to system menus": "הפעל מחדש את היישום כדי להחיל על תפריטי המערכת",
    // System Permissions
    "System Permissions": "הרשאות מערכת",
    "Accessibility access granted": "הרשאת נגישות אושרה",
    "Accessibility access required": "נדרשת הרשאת נגישות",
    "Grant Permission…": "אשר הרשאה…",
    "RememberMyWindows needs Accessibility permission to restore window positions in other apps like Telegram, Chrome, etc.": "RememberMyWindows זקוק להרשאת נגישות כדי לשחזר מיקומי חלונות ביישומים אחרים כמו Telegram, Chrome, וכו׳.",
    "Open System Settings…": "פתח הגדרות מערכת…",
    // Settings Guide Splash Slide
    "Settings Controls": "בקרי הגדרות",
    "Customize triggers, Desktop Toggle (Cmd+D), and Notch notifications in Settings.": "התאם אישית טריגרים, מקש שולחן עבודה (Cmd+D), והתראות מגרעת בהגדרות.",
    "Auto-Restore": "שחזור אוטומטי",
    "Triggers on display connect or app open": "מופעל בחיבור מסך או פתיחת יישום",
    "Desktop Toggle": "הצגת שולחן העבודה",
    "Cmd+D to hide or show all windows": "Cmd+D להסתרה או הצגה של כל החלונות",
    "Notch Alerts": "התראות מגרעת",
    "Pill notifications for layout events": "התראות קפסולה לאירועי סידור חלונות",
    "Restores window layouts automatically when you plug/unplug monitors or open apps.": "משחזר סידורי חלונות באופן אוטומטי בעת חיבור/ניתוק מסכים או פתיחת יישומים.",
    "Press Cmd+D to hide all windows and show desktop. Press again to restore them.": "לחץ Cmd+D להסתרת כל החלונות והצגת שולחן העבודה. לחץ שוב לשחזורם.",
    "Shows an elegant pill-shaped alert sliding out from your screen notch when layouts restore.": "מציג התראת קפסולה אלגנטית המחליקה ממגרעת המסך בעת שחזור סידורים.",
    "Filters log verbosity. Use 'Necessary' to minimize logging, or 'Verbose' for troubleshooting.": "מסנן את פירוט הלוגים. בחר 'חיוני' למינימום רישום, או 'מפורט' לפתרון בעיות.",
    // Log Levels
    "Necessary": "חיוני",
    "Moderate": "מתון",
    "Verbose": "מפורט",
    // Version
    "Version 1.0.0": "גרסה 1.0.0",
    // ContentView
    "Update Layout": "עדכן סידור",
    "Save Layout": "שמור סידור",
    "Restore": "שחזר",
    "VISUAL PREVIEW": "תצוגה מקדימה",
    "Accessibility Permission Required": "נדרשת הרשאת נגישות",
    "To track and restore windows from other apps, please enable RememberMyWindows in System Settings.": "כדי לעקוב ולשחזר חלונות מיישומים אחרים, אפשר את RememberMyWindows בהגדרות המערכת.",
    "Open System Settings": "פתח הגדרות מערכת",
    // LayoutsView
    "LIVE LAYOUT": "סידור חי",
    "SAVED SESSIONS": "מפגשים שמורים",
    "No active layout for this screen config": "אין סידור פעיל לתצורת מסך זו",
    "No saved sessions": "אין מפגשים שמורים",
    "No layouts saved yet": "לא נשמרו סידורים עדיין",
    "Live": "חי",
    "Select a layout to view details": "בחר סידור לצפייה בפרטים",
    "SCREEN ID": "מזהה מסך",
    "Windows": "חלונות",
    "Created": "נוצר",
    "Updated": "עודכן",
    "External Screens Missing": "מסכים חיצוניים חסרים",
    "Connect the required displays to enable restoration of this session.": "חבר את המסכים הנדרשים כדי לאפשר שחזור מפגש זה.",
    "New monitor detected with the same name": "זוהה מסך חדש עם אותו שם",
    "This is a different physical unit than the one in this session.": "זהו יחידה פיזית שונה מזו שבמפגש זה.",
    "Full Screen": "מסך מלא",
    "Click to rename": "לחץ לשינוי שם",
    "Saved&Updated At": "נשמר ועודכן ב",
    "Saved At": "נשמר ב",
    // ActivityView
    "ACTIVITY LOG": "לוג פעילות",
    "Copy Full Log": "העתק לוג מלא",
    "Clear Log": "נקה לוג",
    "History is empty": "ההיסטוריה ריקה",
    // Menu
    "Open RememberMyWindows": "פתח את RememberMyWindows",
    "Restore Default Layout": "שחזר סידור ברירת מחדל",
    "Saved Sessions": "מפגשים שמורים",
    "Quit": "יציאה",
    // System Strings
    "Built-in": "מובנה",
    "Built-in Retina Display": "צג Retina מובנה",
    "Display": "תצוגה",
    "No Display": "אין תצוגה",
]

private let reverseDict: [String: String] = [
    "צג Retina מובנה": "Built-in Retina Display",
    "מובנה": "Built-in",
    "תצוגה": "Display",
    "אין תצוגה": "No Display",
    "סידור חי": "LIVE LAYOUT",
    "מפגשים שמורים": "SAVED SESSIONS",
    "חי": "Live",
    "חלונות": "Windows",
    "נוצר": "Created",
    "עודכן": "Updated",
    "נשמר ועודכן ב": "Saved&Updated At",
    "נשמר ב": "Saved At",
    "לוג פעילות": "ACTIVITY LOG",
    "שוחזר": "Restored",
]

var currentLocale: Locale {
    let langStr = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
    let lang = AppLanguage(rawValue: langStr) ?? .auto
    switch lang {
    case .hebrew:  return Locale(identifier: "he")
    case .english: return Locale(identifier: "en")
    case .auto:    return Locale.current
    }
}
