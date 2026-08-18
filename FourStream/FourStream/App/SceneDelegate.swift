import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private let mediaAuthorizer = SystemMediaAuthorizer()
    private let broadcaster = HaishinKitBroadcaster()
    private let credentialsStore = KeychainCredentialsStore()

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let broadcaster = broadcaster
        let mediaAuthorizer = mediaAuthorizer
        let configurationViewController = ConfigurationViewController(
            viewModel: ConfigurationViewModel(store: credentialsStore),
            makeBroadcastScreen: { credentials in
                BroadcastViewController(
                    viewModel: BroadcastViewModel(
                        credentials: credentials,
                        broadcaster: broadcaster,
                        mediaAuthorizer: mediaAuthorizer
                    )
                )
            }
        )

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = UINavigationController(rootViewController: configurationViewController)
        window.makeKeyAndVisible()
        self.window = window
    }
}
