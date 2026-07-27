import Foundation
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import ItemListUI
import AccountContext

private enum CongyugramModAction: Equatable {
    case premium
    case profile
    case gifts
    case editField(CongyugramProfileField)
    case toggleField(CongyugramProfileField)
    case editCollectible(CongyugramProfileField)
    case toggleCollectible(CongyugramProfileField)
    case usernames
    case addUsername
    case usernameMenu(String)
    case toggleUsername(String)
    case importGift
    case selectCatalogGift(Int64)
    case giftMenu(String)
    case deleteGiftPicker
}

private final class CongyugramModControllerArguments {
    let perform: (CongyugramModAction) -> Void
    let update: (CongyugramModAction, Bool) -> Void

    init(
        perform: @escaping (CongyugramModAction) -> Void,
        update: @escaping (CongyugramModAction, Bool) -> Void
    ) {
        self.perform = perform
        self.update = update
    }
}

private final class CongyugramModControllerHolder {
    weak var controller: ItemListController?
}

private enum CongyugramModEntry: ItemListNodeEntry {
    case header(id: Int32, section: Int32, text: String)
    case text(id: Int32, section: Int32, text: String)
    case disclosure(id: Int32, section: Int32, title: String, label: String, action: CongyugramModAction)
    case toggle(id: Int32, section: Int32, title: String, text: String?, value: Bool, action: CongyugramModAction)
    case action(id: Int32, section: Int32, title: String, destructive: Bool, action: CongyugramModAction)

    var section: ItemListSectionId {
        switch self {
        case let .header(_, section, _), let .text(_, section, _):
            return section
        case let .disclosure(_, section, _, _, _):
            return section
        case let .toggle(_, section, _, _, _, _):
            return section
        case let .action(_, section, _, _, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(id, _, _), let .text(id, _, _):
            return id
        case let .disclosure(id, _, _, _, _):
            return id
        case let .toggle(id, _, _, _, _, _):
            return id
        case let .action(id, _, _, _, _):
            return id
        }
    }

    static func < (lhs: CongyugramModEntry, rhs: CongyugramModEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! CongyugramModControllerArguments
        switch self {
        case let .header(_, section, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: section)
        case let .text(_, section, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: section)
        case let .disclosure(_, section, title, label, action):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: label,
                labelStyle: .text,
                sectionId: section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.perform(action)
                }
            )
        case let .toggle(_, section, title, text, value, action):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                text: text,
                value: value,
                maximumNumberOfLines: 2,
                sectionId: section,
                style: .blocks,
                updated: { value in
                    arguments.update(action, value)
                },
                action: {
                    arguments.perform(action)
                }
            )
        case let .action(_, section, title, destructive, action):
            return ItemListActionItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                kind: destructive ? .destructive : .generic,
                alignment: .center,
                sectionId: section,
                style: .blocks,
                action: {
                    arguments.perform(action)
                }
            )
        }
    }
}

private func congyugramControllerState(
    presentationData: PresentationData,
    title: String,
    entries: [CongyugramModEntry],
    arguments: CongyugramModControllerArguments
) -> (ItemListControllerState, (ItemListNodeState, Any)) {
    var presentationData = presentationData
    presentationData = presentationData.withUpdated(theme: presentationData.theme.withModalBlocksBackground())
    let itemPresentationData = ItemListPresentationData(presentationData)
    let controllerState = ItemListControllerState(
        presentationData: itemPresentationData,
        title: .text(title),
        leftNavigationButton: nil,
        rightNavigationButton: nil,
        backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
    )
    let listState = ItemListNodeState(
        presentationData: itemPresentationData,
        entries: entries,
        style: .blocks,
        animateChanges: true
    )
    return (controllerState, (listState, arguments))
}

private func congyugramPresentTextEditor(
    controller: ViewController?,
    title: String,
    value: String,
    placeholder: String,
    keyboardType: UIKeyboardType = .default,
    completion: @escaping (String) -> Void
) {
    guard let controller else {
        return
    }
    let alert = UIAlertController(title: title, message: nil, preferredStyle: .alert)
    alert.addTextField { textField in
        textField.text = value
        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.clearButtonMode = .whileEditing
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "保存", style: .default, handler: { [weak alert] _ in
        completion(alert?.textFields?.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
    }))
    controller.present(alert, animated: true)
}

private func congyugramPresentCollectibleEditor(
    controller: ViewController?,
    title: String,
    value: CongyugramProfileOverride,
    completion: @escaping (CongyugramProfileOverride) -> Void
) {
    guard let controller else {
        return
    }
    let alert = UIAlertController(title: title, message: "价格和获得时间只在本机资料页展示", preferredStyle: .alert)
    alert.addTextField { textField in
        textField.text = value.collectiblePrice
        textField.placeholder = "竞拍价格，例如 10.0"
        textField.keyboardType = .decimalPad
    }
    alert.addTextField { textField in
        textField.text = value.collectibleTime
        textField.placeholder = "获得时间，例如 7月25日 08:45"
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.addAction(UIAlertAction(title: "保存", style: .default, handler: { [weak alert] _ in
        var updated = value
        updated.collectiblePrice = alert?.textFields?[0].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        updated.collectibleTime = alert?.textFields?[1].text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        completion(updated)
    }))
    controller.present(alert, animated: true)
}

func congyugramModController(context: AccountContext) -> ViewController {
    let holder = CongyugramModControllerHolder()

    let arguments = CongyugramModControllerArguments(
        perform: { [holder] action in
            switch action {
            case .premium:
                break
            case .profile:
                holder.controller?.push(congyugramProfileModController(context: context))
            case .gifts:
                holder.controller?.push(congyugramGiftModController(context: context))
            default:
                break
            }
        },
        update: { action, value in
            if action == .premium {
                CongyugramModSettings.shared.setLocalPremiumEnabled(value)
            }
        }
    )

    let signal = combineLatest(
        queue: .mainQueue(),
        context.sharedContext.presentationData,
        CongyugramModSettings.shared.revision
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let entries: [CongyugramModEntry] = [
            .text(
                id: 0,
                section: 0,
                text: "Congyugram Mod 的效果只保存在当前设备，不会修改 Telegram 服务器上的会员、资料或礼物。"
            ),
            .header(id: 10, section: 1, text: "本地功能"),
            .toggle(
                id: 11,
                section: 1,
                title: "Telegram 高级版本地化",
                text: "会员标志、界面和可本地实现的高级版限制",
                value: CongyugramModSettings.shared.localPremiumEnabled,
                action: .premium
            ),
            .disclosure(id: 12, section: 1, title: "修改主页", label: "", action: .profile),
            .disclosure(id: 13, section: 1, title: "添加礼物", label: "", action: .gifts),
            .text(
                id: 20,
                section: 2,
                text: "服务器校验的功能（例如真正上传高级表情、向其他用户展示 NFT 或提高服务器配额）不会对外生效。"
            )
        ]
        return congyugramControllerState(
            presentationData: presentationData,
            title: "Mod",
            entries: entries,
            arguments: arguments
        )
    }

    let result = ItemListController(context: context, state: signal)
    holder.controller = result
    return result
}

private func congyugramProfileFieldTitle(_ field: CongyugramProfileField) -> String {
    switch field {
    case .phone:
        return "修改手机号码"
    case .username:
        return "修改用户名"
    case .bio:
        return "修改简介"
    case .name:
        return "修改昵称"
    case .birthday:
        return "修改生日"
    }
}

private func congyugramProfileFieldPlaceholder(_ field: CongyugramProfileField) -> String {
    switch field {
    case .phone:
        return "+86 138 0000 0000"
    case .username:
        return "username"
    case .bio:
        return "个人简介"
    case .name:
        return "昵称"
    case .birthday:
        return "2000年1月1日"
    }
}

private func congyugramProfileModController(context: AccountContext) -> ViewController {
    let peerId = context.account.peerId.toInt64()
    let holder = CongyugramModControllerHolder()

    let arguments = CongyugramModControllerArguments(
        perform: { [holder] action in
            switch action {
            case let .editField(field):
                if field == .username {
                    holder.controller?.push(congyugramUsernameModController(context: context))
                    return
                }
                let current = CongyugramModSettings.shared.profileOverride(peerId: peerId, field: field)
                congyugramPresentTextEditor(
                    controller: holder.controller,
                    title: congyugramProfileFieldTitle(field),
                    value: current.value,
                    placeholder: congyugramProfileFieldPlaceholder(field),
                    keyboardType: field == .phone ? .phonePad : .default,
                    completion: { value in
                        var updated = current
                        updated.value = value
                        CongyugramModSettings.shared.setProfileOverride(peerId: peerId, field: field, value: updated)
                    }
                )
            case let .editCollectible(field):
                let current = CongyugramModSettings.shared.profileOverride(peerId: peerId, field: field)
                congyugramPresentCollectibleEditor(
                    controller: holder.controller,
                    title: field == .phone ? "手机号码竞拍资料" : "用户名竞拍资料",
                    value: current,
                    completion: { value in
                        CongyugramModSettings.shared.setProfileOverride(peerId: peerId, field: field, value: value)
                    }
                )
            default:
                break
            }
        },
        update: { action, enabled in
            switch action {
            case let .toggleField(field):
                var current = CongyugramModSettings.shared.profileOverride(peerId: peerId, field: field)
                current.enabled = enabled
                CongyugramModSettings.shared.setProfileOverride(peerId: peerId, field: field, value: current)
            case let .toggleCollectible(field):
                var current = CongyugramModSettings.shared.profileOverride(peerId: peerId, field: field)
                current.collectibleEnabled = enabled
                CongyugramModSettings.shared.setProfileOverride(peerId: peerId, field: field, value: current)
            default:
                break
            }
        }
    )

    let signal = combineLatest(
        queue: .mainQueue(),
        context.sharedContext.presentationData,
        CongyugramModSettings.shared.revision
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        var entries: [CongyugramModEntry] = [
            .text(id: 0, section: 0, text: "打开开关后，当前账号在本机看到的是这里填写的内容；关闭后恢复 Telegram 原资料。"),
            .header(id: 10, section: 1, text: "本地资料")
        ]
        var stableId: Int32 = 11
        for field in CongyugramProfileField.allCases {
            let value = CongyugramModSettings.shared.profileOverride(peerId: peerId, field: field)
            entries.append(.toggle(
                id: stableId,
                section: 1,
                title: congyugramProfileFieldTitle(field),
                text: value.value.isEmpty ? "点击本行填写" : value.value,
                value: value.enabled,
                action: .toggleField(field)
            ))
            stableId += 1
            entries.append(.disclosure(
                id: stableId,
                section: 1,
                title: field == .username ? "用户名列表、排序与 NFT" : "编辑内容",
                label: "",
                action: .editField(field)
            ))
            stableId += 1
            if field == .phone {
                entries.append(.toggle(
                    id: stableId,
                    section: 1,
                    title: "显示为可竞拍号码",
                    text: "价格 \(value.collectiblePrice) · \(value.collectibleTime)",
                    value: value.collectibleEnabled,
                    action: .toggleCollectible(field)
                ))
                stableId += 1
                entries.append(.disclosure(
                    id: stableId,
                    section: 1,
                    title: "设置竞拍价格和时间",
                    label: "",
                    action: .editCollectible(field)
                ))
                stableId += 1
            }
        }
        return congyugramControllerState(
            presentationData: presentationData,
            title: "修改主页",
            entries: entries,
            arguments: arguments
        )
    }

    let result = ItemListController(context: context, state: signal)
    holder.controller = result
    return result
}

private func congyugramUsernameModController(context: AccountContext) -> ViewController {
    let peerId = context.account.peerId.toInt64()
    let holder = CongyugramModControllerHolder()

    let arguments = CongyugramModControllerArguments(
        perform: { [holder] action in
            switch action {
            case .editField(.username):
                let current = CongyugramModSettings.shared.profileOverride(peerId: peerId, field: .username)
                congyugramPresentTextEditor(
                    controller: holder.controller,
                    title: "修改主用户名",
                    value: current.value,
                    placeholder: "username",
                    completion: { value in
                        var updated = current
                        updated.value = value.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                        CongyugramModSettings.shared.setProfileOverride(peerId: peerId, field: .username, value: updated)
                    }
                )
            case .editCollectible(.username):
                let current = CongyugramModSettings.shared.profileOverride(peerId: peerId, field: .username)
                congyugramPresentCollectibleEditor(
                    controller: holder.controller,
                    title: "主用户名竞拍资料",
                    value: current,
                    completion: { value in
                        CongyugramModSettings.shared.setProfileOverride(peerId: peerId, field: .username, value: value)
                    }
                )
            case .addUsername:
                congyugramPresentTextEditor(
                    controller: holder.controller,
                    title: "添加用户名",
                    value: "",
                    placeholder: "username",
                    completion: { value in
                        let username = value.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                        if !username.isEmpty {
                            CongyugramModSettings.shared.addUsername(
                                peerId: peerId,
                                username: CongyugramLocalUsername(username: username)
                            )
                        }
                    }
                )
            case let .usernameMenu(id):
                guard let controller = holder.controller, let item = CongyugramModSettings.shared.usernames(peerId: peerId).first(where: { $0.id == id }) else {
                    return
                }
                let allItems = CongyugramModSettings.shared.usernames(peerId: peerId)
                let index = allItems.firstIndex(where: { $0.id == id }) ?? 0
                let alert = UIAlertController(title: "@\(item.username)", message: "管理本地用户名", preferredStyle: .actionSheet)
                alert.addAction(UIAlertAction(title: "编辑用户名", style: .default, handler: { _ in
                    congyugramPresentTextEditor(
                        controller: controller,
                        title: "编辑用户名",
                        value: item.username,
                        placeholder: "username",
                        completion: { value in
                            var updated = item
                            updated.username = value.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
                            CongyugramModSettings.shared.updateUsername(peerId: peerId, username: updated)
                        }
                    )
                }))
                alert.addAction(UIAlertAction(title: "设置 NFT 价格和时间", style: .default, handler: { _ in
                    let value = CongyugramProfileOverride(
                        enabled: item.active,
                        value: item.username,
                        collectibleEnabled: item.collectibleEnabled,
                        collectiblePrice: item.collectiblePrice,
                        collectibleTime: item.collectibleTime
                    )
                    congyugramPresentCollectibleEditor(controller: controller, title: "用户名竞拍资料", value: value, completion: { value in
                        var updated = item
                        updated.collectibleEnabled = true
                        updated.collectiblePrice = value.collectiblePrice
                        updated.collectibleTime = value.collectibleTime
                        CongyugramModSettings.shared.updateUsername(peerId: peerId, username: updated)
                    })
                }))
                if index > 0 {
                    alert.addAction(UIAlertAction(title: "上移", style: .default, handler: { _ in
                        CongyugramModSettings.shared.moveUsername(peerId: peerId, fromIndex: index, toIndex: index - 1)
                    }))
                }
                if index + 1 < allItems.count {
                    alert.addAction(UIAlertAction(title: "下移", style: .default, handler: { _ in
                        CongyugramModSettings.shared.moveUsername(peerId: peerId, fromIndex: index, toIndex: index + 1)
                    }))
                }
                alert.addAction(UIAlertAction(title: "删除用户名", style: .destructive, handler: { _ in
                    CongyugramModSettings.shared.removeUsername(peerId: peerId, id: id)
                }))
                alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                alert.popoverPresentationController?.sourceView = controller.view
                alert.popoverPresentationController?.sourceRect = CGRect(
                    x: controller.view.bounds.midX,
                    y: controller.view.bounds.maxY - 20.0,
                    width: 1.0,
                    height: 1.0
                )
                controller.present(alert, animated: true)
            default:
                break
            }
        },
        update: { action, enabled in
            switch action {
            case .toggleField(.username):
                var current = CongyugramModSettings.shared.profileOverride(peerId: peerId, field: .username)
                current.enabled = enabled
                CongyugramModSettings.shared.setProfileOverride(peerId: peerId, field: .username, value: current)
            case .toggleCollectible(.username):
                var current = CongyugramModSettings.shared.profileOverride(peerId: peerId, field: .username)
                current.collectibleEnabled = enabled
                CongyugramModSettings.shared.setProfileOverride(peerId: peerId, field: .username, value: current)
            case let .toggleUsername(id):
                if var item = CongyugramModSettings.shared.usernames(peerId: peerId).first(where: { $0.id == id }) {
                    item.active = enabled
                    CongyugramModSettings.shared.updateUsername(peerId: peerId, username: item)
                }
            default:
                break
            }
        }
    )

    let signal = combineLatest(
        queue: .mainQueue(),
        context.sharedContext.presentationData,
        CongyugramModSettings.shared.revision
    )
    |> map { presentationData, _ -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let primary = CongyugramModSettings.shared.profileOverride(peerId: peerId, field: .username)
        var entries: [CongyugramModEntry] = [
            .text(id: 0, section: 0, text: "这些用户名仅在本机展示。点击用户名可编辑、设置 NFT、排序或删除。"),
            .header(id: 10, section: 1, text: "主用户名"),
            .toggle(
                id: 11,
                section: 1,
                title: "本地主用户名",
                text: primary.value.isEmpty ? "点击填写" : "@\(primary.value)",
                value: primary.enabled,
                action: .toggleField(.username)
            ),
            .disclosure(id: 12, section: 1, title: "编辑主用户名", label: "", action: .editField(.username)),
            .toggle(
                id: 13,
                section: 1,
                title: "显示为 NFT 用户名",
                text: "价格 \(primary.collectiblePrice) · \(primary.collectibleTime)",
                value: primary.collectibleEnabled,
                action: .toggleCollectible(.username)
            ),
            .disclosure(id: 14, section: 1, title: "设置竞拍价格和时间", label: "", action: .editCollectible(.username)),
            .header(id: 20, section: 2, text: "更多用户名"),
            .action(id: 21, section: 2, title: "＋ 添加用户名", destructive: false, action: .addUsername)
        ]
        var stableId: Int32 = 30
        for item in CongyugramModSettings.shared.usernames(peerId: peerId) {
            let nftText = item.collectibleEnabled ? " · NFT \(item.collectiblePrice)" : ""
            entries.append(.toggle(
                id: stableId,
                section: 2,
                title: "@\(item.username)",
                text: item.active ? "展示\(nftText)" : "已停用\(nftText)",
                value: item.active,
                action: .toggleUsername(item.id)
            ))
            stableId += 1
            entries.append(.disclosure(
                id: stableId,
                section: 2,
                title: "管理 @\(item.username)",
                label: "",
                action: .usernameMenu(item.id)
            ))
            stableId += 1
        }
        return congyugramControllerState(
            presentationData: presentationData,
            title: "修改用户名",
            entries: entries,
            arguments: arguments
        )
    }

    let result = ItemListController(context: context, state: signal)
    holder.controller = result
    return result
}

private func congyugramGiftAttributeName(_ attribute: StarGift.UniqueGift.Attribute) -> String {
    switch attribute {
    case let .model(name, _, _, _):
        return name
    case let .pattern(name, _, _):
        return name
    case let .backdrop(name, _, _, _, _, _, _):
        return name
    case .originalInfo:
        return "Original"
    }
}

private func congyugramBackdropCatalog() -> [StarGift.UniqueGift.Attribute] {
    let colors: [(String, Int32, UInt32, UInt32, UInt32, UInt32)] = [
        ("Black", -1001, 0x151515, 0x050505, 0x343434, 0xffffff),
        ("Onyx Black", -1002, 0x242424, 0x0b0b0b, 0x444444, 0xffffff),
        ("Electric Purple", -1003, 0x9b5de5, 0x4a167d, 0xc59cff, 0xffffff),
        ("Deep Blue", -1004, 0x2678d9, 0x102a67, 0x65adff, 0xffffff),
        ("Sky Blue", -1005, 0x6ecbff, 0x287cc2, 0xb8e8ff, 0xffffff),
        ("Mint Green", -1006, 0x60d7a7, 0x167451, 0xa7efd4, 0xffffff),
        ("Emerald", -1007, 0x1bbf78, 0x075936, 0x72e4b0, 0xffffff),
        ("Lime", -1008, 0xb7e35b, 0x5d7d12, 0xe4ff9d, 0x172000),
        ("Golden", -1009, 0xf4c24f, 0x9d5b0c, 0xffe59b, 0x2c1a00),
        ("Orange", -1010, 0xff9f43, 0xb64b13, 0xffd19b, 0xffffff),
        ("Coral", -1011, 0xff776d, 0xa72d39, 0xffb8b1, 0xffffff),
        ("Ruby Red", -1012, 0xe9435f, 0x721427, 0xff91a2, 0xffffff),
        ("Rose Pink", -1013, 0xf577ac, 0x9b285f, 0xffb7d5, 0xffffff),
        ("Lavender", -1014, 0xb89af0, 0x5c3e9b, 0xe1d1ff, 0xffffff),
        ("Silver", -1015, 0xbfc7d5, 0x5d6675, 0xe9edf4, 0x15202d),
        ("White", -1016, 0xf4f4f4, 0xbfc2c8, 0xffffff, 0x202020)
    ]
    return colors.map { name, id, inner, outer, pattern, text in
        return .backdrop(
            name: name,
            id: id,
            innerColor: Int32(bitPattern: inner),
            outerColor: Int32(bitPattern: outer),
            patternColor: Int32(bitPattern: pattern),
            textColor: Int32(bitPattern: text),
            rarity: .permille(20)
        )
    }
}

private func congyugramSelectGiftAttribute(
    controller: ViewController,
    title: String,
    attributes: [StarGift.UniqueGift.Attribute],
    completion: @escaping (StarGift.UniqueGift.Attribute) -> Void
) {
    let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
    for attribute in attributes {
        alert.addAction(UIAlertAction(title: congyugramGiftAttributeName(attribute), style: .default, handler: { _ in
            completion(attribute)
        }))
    }
    alert.addAction(UIAlertAction(title: "取消", style: .cancel))
    alert.popoverPresentationController?.sourceView = controller.view
    alert.popoverPresentationController?.sourceRect = CGRect(
        x: controller.view.bounds.midX,
        y: controller.view.bounds.maxY - 20.0,
        width: 1.0,
        height: 1.0
    )
    controller.present(alert, animated: true)
}

private func congyugramMakeLocalGift(
    peerId: EnginePeer.Id,
    baseGift: StarGift.Gift,
    model: StarGift.UniqueGift.Attribute,
    backdrop: StarGift.UniqueGift.Attribute,
    pattern: StarGift.UniqueGift.Attribute,
    number: Int32
) -> ProfileGiftsContext.State.StarGift {
    let token = UUID().uuidString.lowercased()
    let slug = "congyugram-local-\(token)"
    let uniqueGift = StarGift.UniqueGift(
        id: -Int64.random(in: 1 ... Int64.max),
        giftId: baseGift.id,
        title: baseGift.title ?? "Gift",
        number: number,
        slug: slug,
        owner: .peerId(peerId),
        attributes: [model, backdrop, pattern],
        availability: StarGift.UniqueGift.Availability(issued: max(1, number), total: max(50000, number)),
        giftAddress: nil,
        resellAmounts: nil,
        resellForTonOnly: false,
        releasedBy: baseGift.releasedBy,
        valueAmount: nil,
        valueCurrency: nil,
        valueUsdAmount: nil,
        flags: [],
        themePeerId: nil,
        peerColor: nil,
        hostPeerId: nil,
        minOfferStars: nil,
        craftChancePermille: nil
    )
    return ProfileGiftsContext.State.StarGift(
        gift: .unique(uniqueGift),
        reference: .slug(slug: slug),
        fromPeer: nil,
        date: Int32(Date().timeIntervalSince1970),
        text: nil,
        entities: nil,
        nameHidden: false,
        savedToProfile: true,
        pinnedToTop: false,
        convertStars: nil,
        canUpgrade: false,
        canExportDate: nil,
        upgradeStars: nil,
        transferStars: nil,
        canTransferDate: nil,
        canResaleDate: nil,
        collectionIds: nil,
        prepaidUpgradeHash: nil,
        upgradeSeparate: false,
        dropOriginalDetailsStars: nil,
        number: number,
        isRefunded: false,
        canCraftAt: nil
    )
}

private func congyugramMakeImportedLocalGift(
    peerId: EnginePeer.Id,
    gift: StarGift.UniqueGift
) -> ProfileGiftsContext.State.StarGift {
    let slug = "congyugram-local-\(UUID().uuidString.lowercased())"
    let localGift = StarGift.UniqueGift(
        id: -Int64.random(in: 1 ... Int64.max),
        giftId: gift.giftId,
        title: gift.title,
        number: gift.number,
        slug: slug,
        owner: .peerId(peerId),
        attributes: gift.attributes.filter {
            if case .originalInfo = $0 {
                return false
            }
            return true
        },
        availability: gift.availability,
        giftAddress: nil,
        resellAmounts: gift.resellAmounts,
        resellForTonOnly: gift.resellForTonOnly,
        releasedBy: gift.releasedBy,
        valueAmount: gift.valueAmount,
        valueCurrency: gift.valueCurrency,
        valueUsdAmount: gift.valueUsdAmount,
        flags: gift.flags,
        themePeerId: gift.themePeerId,
        peerColor: gift.peerColor,
        hostPeerId: gift.hostPeerId,
        minOfferStars: gift.minOfferStars,
        craftChancePermille: gift.craftChancePermille
    )
    return ProfileGiftsContext.State.StarGift(
        gift: .unique(localGift),
        reference: .slug(slug: slug),
        fromPeer: nil,
        date: Int32(Date().timeIntervalSince1970),
        text: nil,
        entities: nil,
        nameHidden: false,
        savedToProfile: true,
        pinnedToTop: false,
        convertStars: nil,
        canUpgrade: false,
        canExportDate: nil,
        upgradeStars: nil,
        transferStars: nil,
        canTransferDate: nil,
        canResaleDate: nil,
        collectionIds: nil,
        prepaidUpgradeHash: nil,
        upgradeSeparate: false,
        dropOriginalDetailsStars: nil,
        number: gift.number,
        isRefunded: false,
        canCraftAt: nil
    )
}

private func congyugramGiftLabel(_ gift: ProfileGiftsContext.State.StarGift) -> String {
    if case let .unique(uniqueGift) = gift.gift {
        return "\(uniqueGift.title) #\(uniqueGift.number)"
    } else if case let .generic(genericGift) = gift.gift {
        return genericGift.title ?? "Gift"
    }
    return "Gift"
}

private func congyugramGiftModController(context: AccountContext) -> ViewController {
    let peerId = context.account.peerId.toInt64()
    let holder = CongyugramModControllerHolder()
    var catalogById: [Int64: StarGift.Gift] = [:]

    let _ = context.engine.payments.keepStarGiftsUpdated().startStandalone()

    func showGiftBuilder(_ baseGift: StarGift.Gift) {
        guard let controller = holder.controller else {
            return
        }
        let progress = UIAlertController(title: "正在载入礼物属性", message: "请稍候…", preferredStyle: .alert)
        controller.present(progress, animated: true)
        let _ = (context.engine.payments.getStarGiftUpgradeAttributes(giftId: baseGift.id)
        |> take(1)
        |> deliverOnMainQueue).startStandalone(next: { attributes in
            progress.dismiss(animated: true)
            var models = (attributes ?? []).filter {
                if case .model = $0 {
                    return true
                }
                return false
            }
            var backdrops = (attributes ?? []).filter {
                if case .backdrop = $0 {
                    return true
                }
                return false
            }
            var patterns = (attributes ?? []).filter {
                if case .pattern = $0 {
                    return true
                }
                return false
            }
            if models.isEmpty {
                models = [.model(name: "Original", file: baseGift.file, rarity: .permille(10), crafted: false)]
            }
            if patterns.isEmpty {
                patterns = [.pattern(name: "Original", file: baseGift.file, rarity: .permille(10))]
            }
            for builtInBackdrop in congyugramBackdropCatalog() {
                let name = congyugramGiftAttributeName(builtInBackdrop)
                if !backdrops.contains(where: { congyugramGiftAttributeName($0).caseInsensitiveCompare(name) == .orderedSame }) {
                    backdrops.append(builtInBackdrop)
                }
            }

            congyugramSelectGiftAttribute(controller: controller, title: "选择型号", attributes: models, completion: { model in
                congyugramSelectGiftAttribute(controller: controller, title: "选择背景", attributes: backdrops, completion: { backdrop in
                    congyugramSelectGiftAttribute(controller: controller, title: "选择背景符号", attributes: patterns, completion: { pattern in
                        congyugramPresentTextEditor(
                            controller: controller,
                            title: "自定义编号",
                            value: "1234",
                            placeholder: "请输入正整数",
                            keyboardType: .numberPad,
                            completion: { text in
                                guard let number = Int32(text), number > 0 else {
                                    return
                                }
                                let gift = congyugramMakeLocalGift(
                                    peerId: context.account.peerId,
                                    baseGift: baseGift,
                                    model: model,
                                    backdrop: backdrop,
                                    pattern: pattern,
                                    number: number
                                )
                                CongyugramModSettings.shared.addLocalGift(peerId: peerId, gift: gift)
                            }
                        )
                    })
                })
            })
        })
    }

    let arguments = CongyugramModControllerArguments(
        perform: { [holder] action in
            switch action {
            case .importGift:
                congyugramPresentTextEditor(
                    controller: holder.controller,
                    title: "一键导入礼物",
                    value: "",
                    placeholder: "粘贴 t.me/nft/… 礼物链接",
                    completion: { value in
                        var slug = value
                        if let url = URL(string: value), let component = url.pathComponents.last {
                            slug = component
                        } else if let component = value.split(separator: "/").last {
                            slug = String(component)
                        }
                        if let queryIndex = slug.firstIndex(of: "?") {
                            slug = String(slug[..<queryIndex])
                        }
                        guard !slug.isEmpty else {
                            return
                        }
                        let signal: Signal<StarGift.UniqueGift?, NoError> = context.engine.payments.getUniqueStarGift(slug: slug)
                        |> map(Optional.init)
                        |> `catch` { _ in
                            return .single(nil)
                        }
                        let _ = (signal
                        |> deliverOnMainQueue).startStandalone(next: { gift in
                            guard let gift else {
                                return
                            }
                            CongyugramModSettings.shared.addLocalGift(
                                peerId: peerId,
                                gift: congyugramMakeImportedLocalGift(peerId: context.account.peerId, gift: gift)
                            )
                        })
                    }
                )
            case let .selectCatalogGift(id):
                if let gift = catalogById[id] {
                    showGiftBuilder(gift)
                }
            case let .giftMenu(slug):
                guard let controller = holder.controller, let gift = CongyugramModSettings.shared.localGifts(peerId: peerId).first(where: { CongyugramModSettings.shared.localGiftSlug($0) == slug }) else {
                    return
                }
                let isWorn = CongyugramModSettings.shared.wornGift(peerId: peerId).flatMap { CongyugramModSettings.shared.localGiftSlug($0) } == slug
                let alert = UIAlertController(title: congyugramGiftLabel(gift), message: "管理本地礼物", preferredStyle: .actionSheet)
                alert.addAction(UIAlertAction(title: isWorn ? "取消佩戴" : "佩戴到主页", style: .default, handler: { _ in
                    if !isWorn, case let .unique(uniqueGift) = gift.gift {
                        let _ = (context.account.postbox.transaction { transaction in
                            for attribute in uniqueGift.attributes {
                                switch attribute {
                                case let .model(_, file, _, _), let .pattern(_, file, _):
                                    transaction.storeMediaIfNotPresent(media: file)
                                default:
                                    break
                                }
                            }
                        }).startStandalone()
                    }
                    CongyugramModSettings.shared.setWornGift(peerId: peerId, slug: isWorn ? nil : slug)
                }))
                alert.addAction(UIAlertAction(title: gift.pinnedToTop ? "取消置顶" : "置顶", style: .default, handler: { _ in
                    if let reference = gift.reference {
                        _ = CongyugramModSettings.shared.updateLocalGiftPinned(peerId: peerId, reference: reference, pinned: !gift.pinnedToTop)
                    }
                }))
                alert.addAction(UIAlertAction(title: "删除礼物", style: .destructive, handler: { _ in
                    CongyugramModSettings.shared.removeLocalGift(peerId: peerId, slug: slug)
                }))
                alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                alert.popoverPresentationController?.sourceView = controller.view
                alert.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.maxY - 20.0, width: 1.0, height: 1.0)
                controller.present(alert, animated: true)
            case .deleteGiftPicker:
                guard let controller = holder.controller else {
                    return
                }
                let gifts = CongyugramModSettings.shared.localGifts(peerId: peerId)
                let alert = UIAlertController(title: "删除礼物", message: gifts.isEmpty ? "还没有添加本地礼物" : "选择要删除的礼物", preferredStyle: .actionSheet)
                for gift in gifts {
                    guard let slug = CongyugramModSettings.shared.localGiftSlug(gift) else {
                        continue
                    }
                    alert.addAction(UIAlertAction(title: congyugramGiftLabel(gift), style: .destructive, handler: { _ in
                        CongyugramModSettings.shared.removeLocalGift(peerId: peerId, slug: slug)
                    }))
                }
                alert.addAction(UIAlertAction(title: "取消", style: .cancel))
                alert.popoverPresentationController?.sourceView = controller.view
                alert.popoverPresentationController?.sourceRect = CGRect(x: controller.view.bounds.midX, y: controller.view.bounds.maxY - 20.0, width: 1.0, height: 1.0)
                controller.present(alert, animated: true)
            default:
                break
            }
        },
        update: { _, _ in }
    )

    let signal = combineLatest(
        queue: .mainQueue(),
        context.sharedContext.presentationData,
        CongyugramModSettings.shared.revision,
        context.engine.payments.cachedStarGifts()
    )
    |> map { presentationData, _, catalog -> (ItemListControllerState, (ItemListNodeState, Any)) in
        catalogById.removeAll()
        var entries: [CongyugramModEntry] = [
            .text(id: 0, section: 0, text: "复制现有礼物链接可一键导入；导入后的拥有者固定为当前账号。"),
            .action(id: 1, section: 0, title: "粘贴链接并导入", destructive: false, action: .importGift),
            .header(id: 10, section: 1, text: "已添加的礼物")
        ]

        let wornSlug = CongyugramModSettings.shared.wornGift(peerId: peerId).flatMap { CongyugramModSettings.shared.localGiftSlug($0) }
        var stableId: Int32 = 11
        for gift in CongyugramModSettings.shared.localGifts(peerId: peerId) {
            guard let slug = CongyugramModSettings.shared.localGiftSlug(gift) else {
                continue
            }
            var states: [String] = []
            if gift.pinnedToTop {
                states.append("置顶")
            }
            if wornSlug == slug {
                states.append("已佩戴")
            }
            entries.append(.disclosure(
                id: stableId,
                section: 1,
                title: congyugramGiftLabel(gift),
                label: states.joined(separator: " · "),
                action: .giftMenu(slug)
            ))
            stableId += 1
        }

        entries.append(.header(id: 1000, section: 2, text: "选择礼物种类"))
        var catalogStableId: Int32 = 1001
        for gift in catalog ?? [] {
            guard case let .generic(genericGift) = gift else {
                continue
            }
            catalogById[genericGift.id] = genericGift
            entries.append(.disclosure(
                id: catalogStableId,
                section: 2,
                title: genericGift.title ?? "Gift",
                label: "⭐️ \(genericGift.price)",
                action: .selectCatalogGift(genericGift.id)
            ))
            catalogStableId += 1
        }
        entries.append(.action(id: 30000, section: 3, title: "删除礼物", destructive: true, action: .deleteGiftPicker))
        return congyugramControllerState(
            presentationData: presentationData,
            title: "添加礼物",
            entries: entries,
            arguments: arguments
        )
    }

    let result = ItemListController(context: context, state: signal)
    holder.controller = result
    return result
}
