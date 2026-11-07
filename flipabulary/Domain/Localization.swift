import Foundation

enum L10n {
    static func string(_ key: String, language: AppLanguage?) -> String {
        guard let language, !language.isSystem,
              let path = Bundle.main.path(forResource: language.rawValue, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return NSLocalizedString(key, comment: "")
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    static func format(_ key: String, language: AppLanguage?, _ arguments: CVarArg...) -> String {
        String(format: string(key, language: language), arguments: arguments)
    }

    static func date(_ date: Date, language: AppLanguage?) -> String {
        let formatter = DateFormatter()
        formatter.locale = language?.locale ?? Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
