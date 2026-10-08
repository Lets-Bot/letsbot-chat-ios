import Foundation

/// The few native strings shown before the hosted screen loads (everything else is rendered by LetsBot).
enum LocalStrings {
    struct Set { let failed: String; let retry: String; let close: String; let ok: String; let cancel: String }

    private static let table: [String: Set] = [
        "en": .init(failed: "Couldn't load the chat. Check your connection and try again.", retry: "Try again",
                    close: "Close", ok: "OK", cancel: "Cancel"),
        "ar": .init(failed: "تعذّر تحميل المحادثة. تحقّق من الاتصال وحاول مرة أخرى.", retry: "إعادة المحاولة",
                    close: "إغلاق", ok: "حسنًا", cancel: "إلغاء"),
        "es": .init(failed: "No se pudo cargar el chat. Revisa tu conexión e inténtalo de nuevo.", retry: "Reintentar",
                    close: "Cerrar", ok: "Aceptar", cancel: "Cancelar"),
        "pt": .init(failed: "Não foi possível carregar o chat. Verifique sua conexão e tente novamente.",
                    retry: "Tentar novamente", close: "Fechar", ok: "OK", cancel: "Cancelar"),
    ]

    static func strings(for locale: String?) -> Set {
        let code = (locale.flatMap { $0 == "auto" ? nil : $0 } ?? Locale.preferredLanguages.first ?? "en")
            .lowercased().prefix(2)
        return table[String(code)] ?? table["en"]!
    }

    static func isRightToLeft(_ locale: String?) -> Bool {
        let code = (locale.flatMap { $0 == "auto" ? nil : $0 } ?? Locale.preferredLanguages.first ?? "en")
            .lowercased().prefix(2)
        return ["ar", "he", "fa", "ur"].contains(String(code))
    }
}
