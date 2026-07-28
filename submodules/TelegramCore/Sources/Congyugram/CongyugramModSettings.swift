import Foundation
import SwiftSignalKit

public enum CongyugramProfileField: String, Codable, CaseIterable {
    case phone
    case username
    case bio
    case name
    case birthday
}

public struct CongyugramProfileOverride: Codable, Equatable {
    public var enabled: Bool
    public var value: String
    public var collectibleEnabled: Bool
    public var collectiblePrice: String
    public var collectibleTime: String

    public init(
        enabled: Bool = false,
        value: String = "",
        collectibleEnabled: Bool = false,
        collectiblePrice: String = "10.0",
        collectibleTime: String = ""
    ) {
        self.enabled = enabled
        self.value = value
        self.collectibleEnabled = collectibleEnabled
        self.collectiblePrice = collectiblePrice
        self.collectibleTime = collectibleTime
    }
}

public struct CongyugramLocalUsername: Codable, Equatable, Identifiable {
    public let id: String
    public var username: String
    public var active: Bool
    public var collectibleEnabled: Bool
    public var collectiblePrice: String
    public var collectibleTime: String

    public init(
        id: String = UUID().uuidString,
        username: String,
        active: Bool = true,
        collectibleEnabled: Bool = false,
        collectiblePrice: String = "10.0",
        collectibleTime: String = ""
    ) {
        self.id = id
        self.username = username
        self.active = active
        self.collectibleEnabled = collectibleEnabled
        self.collectiblePrice = collectiblePrice
        self.collectibleTime = collectibleTime
    }
}

private struct CongyugramAccountModState: Codable {
    var profile: [String: CongyugramProfileOverride] = [:]
    var usernames: [CongyugramLocalUsername] = []
    var gifts: [ProfileGiftsContext.State.StarGift] = []
    var wornGiftSlug: String?
    var localEmojiStatus: PeerEmojiStatus?
    var hasLocalColors: Bool = false
    var localNameColorRawValue: Int32?
    var localCollectibleColor: PeerCollectibleColor?
    var localBackgroundEmojiId: Int64?
    var localBackgroundEmojiFile: TelegramMediaFile?
    var localProfileColorRawValue: Int32?
    var localProfileBackgroundEmojiId: Int64?
    var localProfileBackgroundEmojiFile: TelegramMediaFile?
    var originalPinnedDialogIds: [Int64]?
    var extraPinnedDialogIds: [Int64] = []
}

private struct CongyugramStoredModState: Codable {
    var localPremiumEnabled: Bool = false
    var registeredAccountPeerIds: [Int64] = []
    var accounts: [String: CongyugramAccountModState] = [:]
}

public final class CongyugramModSettings {
    public static let shared = CongyugramModSettings()

    private let storageKey = "Congyugram.ModSettings.v1"
    private let lock = NSLock()
    private var state: CongyugramStoredModState
    private var revisionValue: Int = 0
    private let revisionPromise = ValuePromise<Int>(0, ignoreRepeated: true)

    public var revision: Signal<Int, NoError> {
        return self.revisionPromise.get()
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: self.storageKey),
           let decoded = try? JSONDecoder().decode(CongyugramStoredModState.self, from: data) {
            self.state = decoded
        } else {
            self.state = CongyugramStoredModState()
        }
    }

    private func accountKey(_ peerId: Int64) -> String {
        return String(peerId)
    }

    private func read<T>(_ f: (CongyugramStoredModState) -> T) -> T {
        self.lock.lock()
        let result = f(self.state)
        self.lock.unlock()
        return result
    }

    private func update(_ f: (inout CongyugramStoredModState) -> Void) {
        self.lock.lock()
        f(&self.state)
        if let data = try? JSONEncoder().encode(self.state) {
            UserDefaults.standard.set(data, forKey: self.storageKey)
        }
        self.revisionValue &+= 1
        let revisionValue = self.revisionValue
        self.lock.unlock()
        self.revisionPromise.set(revisionValue)
    }

    public func registerAccount(peerId: Int64) {
        self.update { state in
            if !state.registeredAccountPeerIds.contains(peerId) {
                state.registeredAccountPeerIds.append(peerId)
            }
            if state.accounts[self.accountKey(peerId)] == nil {
                state.accounts[self.accountKey(peerId)] = CongyugramAccountModState()
            }
        }
    }

    public func isRegisteredAccount(peerId: Int64) -> Bool {
        return self.read { $0.registeredAccountPeerIds.contains(peerId) }
    }

    public var localPremiumEnabled: Bool {
        return self.read { $0.localPremiumEnabled }
    }

    public func setLocalPremiumEnabled(_ value: Bool) {
        self.update { $0.localPremiumEnabled = value }
    }

    public func isLocalPremiumPeer(peerId: Int64) -> Bool {
        return self.read { state in
            state.localPremiumEnabled && state.registeredAccountPeerIds.contains(peerId)
        }
    }

    public func profileOverride(peerId: Int64, field: CongyugramProfileField) -> CongyugramProfileOverride {
        return self.read { state in
            state.accounts[self.accountKey(peerId)]?.profile[field.rawValue] ?? CongyugramProfileOverride()
        }
    }

    public func setProfileOverride(peerId: Int64, field: CongyugramProfileField, value: CongyugramProfileOverride) {
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            account.profile[field.rawValue] = value
            state.accounts[self.accountKey(peerId)] = account
        }
    }

    public func effectiveProfileValue(peerId: Int64, field: CongyugramProfileField) -> String? {
        let item = self.profileOverride(peerId: peerId, field: field)
        return item.enabled && !item.value.isEmpty ? item.value : nil
    }

    public func usernames(peerId: Int64) -> [CongyugramLocalUsername] {
        return self.read { $0.accounts[self.accountKey(peerId)]?.usernames ?? [] }
    }

    public func addUsername(peerId: Int64, username: CongyugramLocalUsername) {
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            account.usernames.append(username)
            state.accounts[self.accountKey(peerId)] = account
        }
    }

    public func updateUsername(peerId: Int64, username: CongyugramLocalUsername) {
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            if let index = account.usernames.firstIndex(where: { $0.id == username.id }) {
                account.usernames[index] = username
            }
            state.accounts[self.accountKey(peerId)] = account
        }
    }

    public func removeUsername(peerId: Int64, id: String) {
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            account.usernames.removeAll(where: { $0.id == id })
            state.accounts[self.accountKey(peerId)] = account
        }
    }

    public func moveUsername(peerId: Int64, fromIndex: Int, toIndex: Int) {
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            guard fromIndex >= 0, fromIndex < account.usernames.count, toIndex >= 0, toIndex < account.usernames.count else {
                return
            }
            let item = account.usernames.remove(at: fromIndex)
            account.usernames.insert(item, at: toIndex)
            state.accounts[self.accountKey(peerId)] = account
        }
    }

    public func effectiveUsername(peerId: Int64) -> String? {
        if let primary = self.effectiveProfileValue(peerId: peerId, field: .username) {
            return primary
        }
        return self.usernames(peerId: peerId).first(where: { $0.active })?.username
    }

    private func normalizedUsername(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasPrefix("@") {
            result.removeFirst()
        }
        return result.lowercased()
    }

    private func normalizedPhoneNumber(_ value: String) -> String {
        return value.filter { $0.isNumber }
    }

    private func collectiblePurchaseDate(_ value: String) -> Int32 {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let timestamp = Int32(text), timestamp > 0 {
            return timestamp
        }

        let formats = [
            "yyyy 年 M 月 d 日",
            "yyyy年M月d日",
            "yyyy-MM-dd",
            "yyyy-MM-dd HH:mm",
            "yyyy/M/d HH:mm",
            "yyyy年M月d日 HH:mm",
            "M月d日 HH:mm",
            "MM-dd HH:mm"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.timeZone = TimeZone.current
            formatter.dateFormat = format
            if let date = formatter.date(from: text) {
                var resolvedDate = date
                if !format.contains("yyyy") {
                    let calendar = Calendar.current
                    let currentYear = calendar.component(.year, from: Date())
                    var components = calendar.dateComponents([.month, .day, .hour, .minute], from: date)
                    components.year = currentYear
                    resolvedDate = calendar.date(from: components) ?? date
                }
                return Int32(clamping: Int64(resolvedDate.timeIntervalSince1970))
            }
        }
        return Int32(clamping: Int64(Date().timeIntervalSince1970))
    }

    private func collectibleInfo(
        subject: TelegramCollectibleItemInfo.Subject,
        price: String,
        time: String,
        url: String
    ) -> TelegramCollectibleItemInfo {
        let normalizedPrice = price.replacingOccurrences(of: ",", with: ".")
        let tonAmount = max(0.0, Double(normalizedPrice) ?? 10.0)
        return TelegramCollectibleItemInfo(
            subject: subject,
            purchaseDate: self.collectiblePurchaseDate(time),
            currency: "USD",
            currencyAmount: Int64((tonAmount * 148.5).rounded()),
            cryptoCurrency: "TON",
            cryptoCurrencyAmount: Int64((tonAmount * 1_000_000_000.0).rounded()),
            url: url
        )
    }

    public func localCollectibleUsernameInfo(peerId: Int64, username: String) -> TelegramCollectibleItemInfo? {
        let normalized = self.normalizedUsername(username)
        guard !normalized.isEmpty else {
            return nil
        }

        let primary = self.profileOverride(peerId: peerId, field: .username)
        if primary.enabled && primary.collectibleEnabled && self.normalizedUsername(primary.value) == normalized {
            return self.collectibleInfo(
                subject: .username(primary.value),
                price: primary.collectiblePrice,
                time: primary.collectibleTime,
                url: "https://fragment.com/username/\(normalized)"
            )
        }
        if let item = self.usernames(peerId: peerId).first(where: {
            $0.active && $0.collectibleEnabled && self.normalizedUsername($0.username) == normalized
        }) {
            return self.collectibleInfo(
                subject: .username(item.username),
                price: item.collectiblePrice,
                time: item.collectibleTime,
                url: "https://fragment.com/username/\(normalized)"
            )
        }
        return nil
    }

    public func localCollectiblePhoneNumberInfo(peerId: Int64, phoneNumber: String) -> TelegramCollectibleItemInfo? {
        let normalized = self.normalizedPhoneNumber(phoneNumber)
        guard !normalized.isEmpty else {
            return nil
        }
        let item = self.profileOverride(peerId: peerId, field: .phone)
        guard item.enabled && item.collectibleEnabled && self.normalizedPhoneNumber(item.value) == normalized else {
            return nil
        }
        return self.collectibleInfo(
            subject: .phoneNumber(item.value),
            price: item.collectiblePrice,
            time: item.collectibleTime,
            url: "https://fragment.com/number/\(normalized)"
        )
    }

    public func localGifts(peerId: Int64) -> [ProfileGiftsContext.State.StarGift] {
        return self.read { state in
            let account = state.accounts[self.accountKey(peerId)]
            return (account?.gifts ?? []).map { gift in
                var result = gift
                if let slug = self.localGiftSlug(result), slug == account?.wornGiftSlug, result.pinnedToTop {
                    result = result.withPinnedToTop(false)
                }
                if self.localGiftSlug(result) != nil, case .unique = result.gift, result.transferStars == nil {
                    result = result.withTransferStars(0)
                }
                return result
            }
        }
    }

    public func addLocalGift(peerId: Int64, gift: ProfileGiftsContext.State.StarGift) {
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            guard !account.gifts.contains(where: { self.localGiftSlug($0) == self.localGiftSlug(gift) }) else {
                return
            }
            account.gifts.insert(gift, at: 0)
            state.accounts[self.accountKey(peerId)] = account
        }
    }

    public func removeLocalGift(peerId: Int64, slug: String) {
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            account.gifts.removeAll(where: { self.localGiftSlug($0) == slug })
            if account.wornGiftSlug == slug {
                account.wornGiftSlug = nil
            }
            state.accounts[self.accountKey(peerId)] = account
        }
    }

    public func updateLocalGiftSavedToProfile(peerId: Int64, reference: StarGiftReference, added: Bool) -> Bool {
        return self.updateLocalGift(peerId: peerId, reference: reference) { gift in
            gift.withSavedToProfile(added).withPinnedToTop(added ? gift.pinnedToTop : false)
        }
    }

    public func updateLocalGiftPinned(peerId: Int64, reference: StarGiftReference, pinned: Bool) -> Bool {
        var found = false
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            if let index = account.gifts.firstIndex(where: { $0.reference == reference }) {
                let gift = account.gifts[index]
                account.gifts[index] = gift.withPinnedToTop(pinned).withSavedToProfile(pinned ? true : gift.savedToProfile)
                if pinned, let slug = self.localGiftSlug(gift), account.wornGiftSlug == slug {
                    account.wornGiftSlug = nil
                }
                found = true
            }
            state.accounts[self.accountKey(peerId)] = account
        }
        return found
    }

    @discardableResult
    private func updateLocalGift(
        peerId: Int64,
        reference: StarGiftReference,
        transform: (ProfileGiftsContext.State.StarGift) -> ProfileGiftsContext.State.StarGift
    ) -> Bool {
        var found = false
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            if let index = account.gifts.firstIndex(where: { $0.reference == reference }) {
                account.gifts[index] = transform(account.gifts[index])
                found = true
            }
            state.accounts[self.accountKey(peerId)] = account
        }
        return found
    }

    public func setWornGift(peerId: Int64, slug: String?) {
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            account.wornGiftSlug = slug
            if let slug {
                if let index = account.gifts.firstIndex(where: { self.localGiftSlug($0) == slug }) {
                    account.gifts[index] = account.gifts[index].withPinnedToTop(false).withSavedToProfile(true)
                }
                account.localEmojiStatus = nil
            }
            state.accounts[self.accountKey(peerId)] = account
        }
    }

    public func wornGift(peerId: Int64) -> ProfileGiftsContext.State.StarGift? {
        return self.read { state in
            guard let account = state.accounts[self.accountKey(peerId)], let slug = account.wornGiftSlug else {
                return nil
            }
            return account.gifts.first(where: { self.localGiftSlug($0) == slug })
        }
    }

    public func wornGiftEmojiStatus(peerId: Int64) -> PeerEmojiStatus? {
        guard let gift = self.wornGift(peerId: peerId), case let .unique(uniqueGift) = gift.gift else {
            return nil
        }
        var modelFile: TelegramMediaFile?
        var patternFile: TelegramMediaFile?
        var colors: (Int32, Int32, Int32, Int32)?
        for attribute in uniqueGift.attributes {
            switch attribute {
            case let .model(_, file, _, _):
                modelFile = file
            case let .pattern(_, file, _):
                patternFile = file
            case let .backdrop(_, _, innerColor, outerColor, patternColor, textColor, _):
                colors = (innerColor, outerColor, patternColor, textColor)
            case .originalInfo:
                break
            }
        }
        guard let modelFile, let patternFile, let colors else {
            return nil
        }
        return PeerEmojiStatus(
            content: .starGift(
                id: uniqueGift.id,
                fileId: modelFile.fileId.id,
                title: uniqueGift.title,
                slug: uniqueGift.slug,
                patternFileId: patternFile.fileId.id,
                innerColor: colors.0,
                outerColor: colors.1,
                patternColor: colors.2,
                textColor: colors.3
            ),
            expirationDate: nil
        )
    }

    public func wornGiftPatternFile(peerId: Int64) -> TelegramMediaFile? {
        guard let gift = self.wornGift(peerId: peerId), case let .unique(uniqueGift) = gift.gift else {
            return nil
        }
        for attribute in uniqueGift.attributes {
            if case let .pattern(_, file, _) = attribute {
                return file
            }
        }
        return nil
    }

    public func localEmojiStatus(peerId: Int64) -> PeerEmojiStatus? {
        return self.read { $0.accounts[self.accountKey(peerId)]?.localEmojiStatus }
    }

    public func setLocalEmojiStatus(peerId: Int64, status: PeerEmojiStatus?) {
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            account.localEmojiStatus = status
            account.wornGiftSlug = nil
            state.accounts[self.accountKey(peerId)] = account
        }
    }

    public func setLocalColors(
        peerId: Int64,
        nameColor: PeerColor,
        backgroundEmojiId: Int64?,
        backgroundEmojiFile: TelegramMediaFile?,
        profileColor: PeerNameColor?,
        profileBackgroundEmojiId: Int64?,
        profileBackgroundEmojiFile: TelegramMediaFile?
    ) {
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            account.hasLocalColors = true
            switch nameColor {
            case let .preset(color):
                account.localNameColorRawValue = color.rawValue
                account.localCollectibleColor = nil
            case let .collectible(color):
                account.localNameColorRawValue = nil
                account.localCollectibleColor = color
            }
            let previousBackgroundEmojiFile = account.localBackgroundEmojiFile
            let previousProfileBackgroundEmojiFile = account.localProfileBackgroundEmojiFile
            account.localBackgroundEmojiId = backgroundEmojiId
            if let backgroundEmojiFile, backgroundEmojiFile.fileId.id == backgroundEmojiId {
                account.localBackgroundEmojiFile = backgroundEmojiFile
            } else if previousBackgroundEmojiFile?.fileId.id != backgroundEmojiId {
                account.localBackgroundEmojiFile = nil
            }
            account.localProfileColorRawValue = profileColor?.rawValue
            account.localProfileBackgroundEmojiId = profileBackgroundEmojiId
            if let profileBackgroundEmojiFile, profileBackgroundEmojiFile.fileId.id == profileBackgroundEmojiId {
                account.localProfileBackgroundEmojiFile = profileBackgroundEmojiFile
            } else if previousProfileBackgroundEmojiFile?.fileId.id != profileBackgroundEmojiId {
                account.localProfileBackgroundEmojiFile = nil
            }
            state.accounts[self.accountKey(peerId)] = account
        }
    }

    public func setLocalColorFiles(
        peerId: Int64,
        backgroundEmojiFile: TelegramMediaFile?,
        profileBackgroundEmojiFile: TelegramMediaFile?
    ) {
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            if let backgroundEmojiFile, backgroundEmojiFile.fileId.id == account.localBackgroundEmojiId {
                account.localBackgroundEmojiFile = backgroundEmojiFile
            }
            if let profileBackgroundEmojiFile, profileBackgroundEmojiFile.fileId.id == account.localProfileBackgroundEmojiId {
                account.localProfileBackgroundEmojiFile = profileBackgroundEmojiFile
            }
            state.accounts[self.accountKey(peerId)] = account
        }
    }

    public func localNameColor(peerId: Int64) -> PeerColor? {
        return self.read { state in
            guard let account = state.accounts[self.accountKey(peerId)], account.hasLocalColors else {
                return nil
            }
            if let color = account.localCollectibleColor {
                return .collectible(color)
            } else if let rawValue = account.localNameColorRawValue {
                return .preset(PeerNameColor(rawValue: rawValue))
            } else {
                return nil
            }
        }
    }

    public func hasLocalColors(peerId: Int64) -> Bool {
        return self.read { state in
            state.accounts[self.accountKey(peerId)]?.hasLocalColors ?? false
        }
    }

    public func localBackgroundEmojiId(peerId: Int64) -> Int64? {
        return self.read { state in
            guard let account = state.accounts[self.accountKey(peerId)], account.hasLocalColors else {
                return nil
            }
            return account.localBackgroundEmojiId
        }
    }

    public func localProfileColor(peerId: Int64) -> PeerNameColor? {
        return self.read { state in
            guard let account = state.accounts[self.accountKey(peerId)], account.hasLocalColors, let rawValue = account.localProfileColorRawValue else {
                return nil
            }
            return PeerNameColor(rawValue: rawValue)
        }
    }

    public func localProfileBackgroundEmojiId(peerId: Int64) -> Int64? {
        return self.read { state in
            guard let account = state.accounts[self.accountKey(peerId)], account.hasLocalColors else {
                return nil
            }
            return account.localProfileBackgroundEmojiId
        }
    }

    public func localProfileBackgroundEmojiFile(peerId: Int64) -> TelegramMediaFile? {
        return self.read { state in
            guard let account = state.accounts[self.accountKey(peerId)], account.hasLocalColors else {
                return nil
            }
            return account.localProfileBackgroundEmojiFile
        }
    }

    public func localGiftSlug(_ gift: ProfileGiftsContext.State.StarGift) -> String? {
        if case let .unique(uniqueGift) = gift.gift, uniqueGift.slug.hasPrefix("congyugram-local-") {
            return uniqueGift.slug
        }
        if case let .slug(slug) = gift.reference, slug.hasPrefix("congyugram-local-") {
            return slug
        }
        return nil
    }

    public func isLocalGift(reference: StarGiftReference) -> Bool {
        if case let .slug(slug) = reference {
            return slug.hasPrefix("congyugram-local-")
        }
        return false
    }

    public func extraPinnedDialogIds(peerId: Int64) -> [Int64] {
        return self.read { $0.accounts[self.accountKey(peerId)]?.extraPinnedDialogIds ?? [] }
    }

    public func originalPinnedDialogIds(peerId: Int64) -> [Int64]? {
        return self.read { $0.accounts[self.accountKey(peerId)]?.originalPinnedDialogIds }
    }

    public func captureOriginalPinnedDialogIds(peerId: Int64, ids: [Int64]) {
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            if account.originalPinnedDialogIds == nil {
                account.originalPinnedDialogIds = ids
            }
            state.accounts[self.accountKey(peerId)] = account
        }
    }

    public func setExtraPinnedDialogIds(peerId: Int64, ids: [Int64]) {
        self.update { state in
            var account = state.accounts[self.accountKey(peerId)] ?? CongyugramAccountModState()
            account.extraPinnedDialogIds = Array(ids.prefix(10))
            state.accounts[self.accountKey(peerId)] = account
        }
    }
}
