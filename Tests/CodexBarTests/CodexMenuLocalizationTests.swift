import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct CodexMenuLocalizationTests {
    @Test
    func `codex login and account submenu labels localize in menu actions`() throws {
        try CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            let settings = self.makeSettings(suite: "CodexMenuLocalizationTests-actions")
            let managedAccount = ManagedCodexAccount(
                id: UUID(),
                email: "managed@example.com",
                managedHomePath: "/tmp/managed-home",
                createdAt: 1,
                updatedAt: 2,
                lastAuthenticatedAt: 2)
            let storeURL = try self.makeManagedAccountStoreURL(accounts: [managedAccount])
            defer {
                settings._test_managedCodexAccountStoreURL = nil
                settings._test_liveSystemCodexAccount = nil
                try? FileManager.default.removeItem(at: storeURL)
            }

            settings._test_managedCodexAccountStoreURL = storeURL
            settings._test_liveSystemCodexAccount = ObservedSystemCodexAccount(
                email: "live@example.com",
                codexHomePath: "/Users/test/.codex",
                observedAt: Date())
            settings.codexActiveSource = .liveSystem

            let store = UsageStore(
                fetcher: UsageFetcher(),
                browserDetection: BrowserDetection(cacheTTL: 0),
                settings: settings)
            let implementation = CodexProviderImplementation()
            let login = implementation.loginMenuAction(context: ProviderMenuLoginContext(
                provider: .codex,
                store: store,
                settings: settings,
                account: AccountInfo(email: nil, plan: nil)))
            #expect(login?.label == "添加账户…")

            var entries: [ProviderMenuEntry] = []
            implementation.appendActionMenuEntries(context: ProviderMenuActionContext(
                provider: .codex,
                store: store,
                settings: settings,
                account: AccountInfo(email: nil, plan: nil),
                managedCodexAccountCoordinator: nil,
                codexAccountPromotionCoordinator: nil), entries: &entries)

            let submenuTitle = entries.compactMap { entry -> String? in
                guard case let .submenu(title, _, _) = entry else { return nil }
                return title
            }.first
            #expect(submenuTitle == "系统账户")
        }
    }

    @Test
    func `codex card model localizes known codex-owned menu text`() throws {
        try CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let metadata = try #require(ProviderDefaults.metadata[.codex])
            let snapshot = UsageSnapshot(
                primary: RateWindow(
                    usedPercent: 2,
                    windowMinutes: 300,
                    resetsAt: now.addingTimeInterval(4 * 60 * 60),
                    resetDescription: nil),
                secondary: RateWindow(
                    usedPercent: 4,
                    windowMinutes: 10080,
                    resetsAt: now.addingTimeInterval(6 * 24 * 60 * 60),
                    resetDescription: nil),
                tertiary: nil,
                extraRateWindows: [
                    NamedRateWindow(
                        id: "codex-spark",
                        title: "Codex Spark 5-hour",
                        window: RateWindow(
                            usedPercent: 30,
                            windowMinutes: 300,
                            resetsAt: now.addingTimeInterval(60 * 60),
                            resetDescription: nil)),
                ],
                updatedAt: now,
                identity: ProviderIdentitySnapshot(
                    providerID: .codex,
                    accountEmail: "user@example.com",
                    accountOrganization: nil,
                    loginMethod: "Pro"))
            let projection = CodexConsumerProjection.make(
                surface: .liveCard,
                context: CodexConsumerProjection.Context(
                    snapshot: snapshot,
                    rawUsageError: nil,
                    liveCredits: nil,
                    rawCreditsError: nil,
                    liveDashboard: nil,
                    rawDashboardError: nil,
                    dashboardAttachmentAuthorized: false,
                    dashboardRequiresLogin: false,
                    now: now))

            let model = UsageMenuCardView.Model.make(.init(
                provider: .codex,
                metadata: metadata,
                snapshot: snapshot,
                codexProjection: projection,
                credits: nil,
                creditsError: nil,
                dashboard: nil,
                dashboardError: nil,
                tokenSnapshot: nil,
                tokenError: nil,
                account: AccountInfo(email: "user@example.com", plan: "Pro"),
                isRefreshing: false,
                lastError: nil,
                usageBarsShowUsed: false,
                resetTimeDisplayStyle: .countdown,
                tokenCostUsageEnabled: false,
                showOptionalCreditsAndExtraUsage: true,
                hidePersonalInfo: false,
                now: now))

            #expect(model.metrics.first { $0.id == "primary" }?.title == "会话")
            #expect(model.metrics.first { $0.id == "secondary" }?.title == "每周")
            #expect(model.metrics.first { $0.id == "codex-spark" }?.title == "Codex Spark 5 小时")
            #expect(model.email == "user@example.com")
            #expect(model.planText == "Pro 20x")
        }
    }

    @Test
    func `codex sanitized menu errors preserve cached suffix`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("zh-Hans") {
            let message = CodexUIErrorMapper.userFacingMessage(
                "Last Codex credits refresh failed: Codex connection failed: failed to fetch codex rate limits: " +
                    "GET https://chatgpt.com/backend-api/wham/usage failed: 500; body={} " +
                    "Cached values from 2m ago.")

            #expect(message == "Codex 用量暂时不可用。请尝试刷新。 Cached values from 2m ago.")
        }
    }

    @Test
    func `codex menu text falls back to original english when language is unavailable`() {
        CodexBarLocalizationOverride.$appLanguage.withValue("fr") {
            let settings = self.makeSettings(suite: "CodexMenuLocalizationTests-fallback")
            let store = UsageStore(
                fetcher: UsageFetcher(),
                browserDetection: BrowserDetection(cacheTTL: 0),
                settings: settings)
            let implementation = CodexProviderImplementation()
            let login = implementation.loginMenuAction(context: ProviderMenuLoginContext(
                provider: .codex,
                store: store,
                settings: settings,
                account: AccountInfo(email: nil, plan: nil)))
            #expect(login?.label == "Add Account...")

            let message = CodexUIErrorMapper.userFacingMessage(
                "Last Codex credits refresh failed: Codex connection failed: failed to fetch codex rate limits: " +
                    "GET https://chatgpt.com/backend-api/wham/usage failed: 500; body={} " +
                    "Cached values from 2m ago.")

            #expect(message == "Codex usage is temporarily unavailable. Try refreshing. Cached values from 2m ago.")
        }
    }

    private func makeSettings(suite: String) -> SettingsStore {
        let defaults = UserDefaults(suiteName: "\(suite)-\(UUID().uuidString)")!
        defaults.removePersistentDomain(forName: suite)
        return SettingsStore(
            userDefaults: defaults,
            configStore: testConfigStore(suiteName: suite),
            zaiTokenStore: NoopZaiTokenStore(),
            syntheticTokenStore: NoopSyntheticTokenStore())
    }

    private func makeManagedAccountStoreURL(accounts: [ManagedCodexAccount]) throws -> URL {
        let storeURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = FileManagedCodexAccountStore(fileURL: storeURL)
        try store.storeAccounts(ManagedCodexAccountSet(
            version: FileManagedCodexAccountStore.currentVersion,
            accounts: accounts))
        return storeURL
    }
}
