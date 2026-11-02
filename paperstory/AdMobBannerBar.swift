#if os(iOS)
import SwiftUI
import GoogleMobileAds
import UserMessagingPlatform
import Observation

@MainActor
@Observable
final class AdvertisingController {
    private(set) var isReady = false
    private(set) var requiresPrivacyOptions = false
    private var didPrepare = false

    func prepare() async {
        guard !didPrepare else { return }
        didPrepare = true
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: RequestParameters())
            try await ConsentForm.loadAndPresentIfRequired(from: nil)
        } catch {
            print("Advertising consent update failed:", error.localizedDescription)
        }
        requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        guard ConsentInformation.shared.canRequestAds else { return }
        _ = await MobileAds.shared.start()
        isReady = true
    }

    func showPrivacyOptions() async {
        do {
            try await ConsentForm.presentPrivacyOptionsForm(from: nil)
        } catch {
            print("Advertising privacy options failed:", error.localizedDescription)
        }
        requiresPrivacyOptions = ConsentInformation.shared.privacyOptionsRequirementStatus == .required
        isReady = ConsentInformation.shared.canRequestAds
    }
}

struct AdMobBannerBar: View {
    let controller: AdvertisingController
    @State private var bannerLoaded = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if !bannerLoaded || !controller.isReady {
                    Text("広告")
                        .font(.caption2)
                        .foregroundStyle(AppPalette.ink.opacity(0.5))
                }
                if controller.isReady,
                   let unitID = Bundle.main.object(forInfoDictionaryKey: "AdMobBannerAdUnitID") as? String {
                    BannerHost(adUnitID: unitID) { bannerLoaded = $0 }
                        .frame(width: 320, height: 50)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            if controller.requiresPrivacyOptions {
                Button("広告のプライバシー設定") {
                    Task { await controller.showPrivacyOptions() }
                }
                .font(.caption)
                .frame(minHeight: 44)
                .tint(AppPalette.ink)
            }
        }
        .padding(.top, 10)
        .background(AppPalette.background)
        .overlay(alignment: .top) {
            Rectangle().fill(AppPalette.ink.opacity(0.12)).frame(height: 1)
        }
        .task {
            guard !Self.adsHiddenForScreenshots else { return }
            await controller.prepare()
        }
    }

    /// ストア用スクリーンショットの撮影専用。Debugビルドで起動引数 -hideAds を付けたときだけ、広告を読み込まない。
    private static var adsHiddenForScreenshots: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-hideAds")
        #else
        false
        #endif
    }
}

private struct BannerHost: UIViewControllerRepresentable {
    let adUnitID: String
    let onLoad: (Bool) -> Void

    func makeUIViewController(context: Context) -> BannerViewController {
        BannerViewController(adUnitID: adUnitID, onLoad: onLoad)
    }

    func updateUIViewController(_ uiViewController: BannerViewController, context: Context) {}
}

private final class BannerViewController: UIViewController, BannerViewDelegate {
    private let banner = BannerView(adSize: AdSizeBanner)
    private let adUnitID: String
    private let onLoad: (Bool) -> Void
    private var requested = false

    init(adUnitID: String, onLoad: @escaping (Bool) -> Void) {
        self.adUnitID = adUnitID
        self.onLoad = onLoad
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(adUnitID:onLoad:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        banner.adUnitID = adUnitID
        banner.rootViewController = self
        banner.delegate = self
        banner.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            banner.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            banner.widthAnchor.constraint(equalToConstant: 320),
            banner.heightAnchor.constraint(equalToConstant: 50)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !requested else { return }
        requested = true
        banner.load(Request())
    }

    func bannerViewDidReceiveAd(_ bannerView: BannerView) {
        onLoad(true)
        print("AdMob banner loaded.")
    }

    func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
        onLoad(false)
        print("Banner ad failed:", error.localizedDescription)
    }
}

#endif
