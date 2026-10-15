import Contacts
import ContactsUI
import UIKit

/// Picks a contact from the iPhone address book (no Contacts permission needed with the system picker).
final class ContactImporter: NSObject, CNContactPickerDelegate {
    struct Result {
        var name: String
        var nickname: String
        var photo: Data?
        var birthday: Date?
    }

    static let shared = ContactImporter()
    private var completion: ((Result?) -> Void)?

    func present(completion: @escaping (Result?) -> Void) {
        guard let presenter = Self.topViewController() else {
            completion(nil)
            return
        }
        self.completion = completion
        let picker = CNContactPickerViewController()
        picker.delegate = self
        presenter.present(picker, animated: true)
    }

    func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
        let name = CNContactFormatter.string(from: contact, style: .fullName)
            ?? [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        var photo: Data?
        if contact.isKeyAvailable(CNContactImageDataKey) {
            photo = contact.imageData
        }
        if photo == nil, contact.isKeyAvailable(CNContactThumbnailImageDataKey) {
            photo = contact.thumbnailImageData
        }
        var birthday: Date?
        if contact.isKeyAvailable(CNContactBirthdayKey), let components = contact.birthday, components.year != nil {
            birthday = Calendar.current.date(from: components)
        }
        let nickname = contact.isKeyAvailable(CNContactNicknameKey) ? contact.nickname : ""
        completion?(Result(name: name, nickname: nickname, photo: photo.flatMap { ImageUtil.avatarData(from: $0) }, birthday: birthday))
        completion = nil
    }

    func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
        completion?(nil)
        completion = nil
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        var top = window?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

enum ImageUtil {
    /// Downscales a photo to a small JPEG suitable for an avatar.
    static func avatarData(from data: Data, maxSide: CGFloat = 600) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let longest = max(image.size.width, image.size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: 0.8)
    }
}
