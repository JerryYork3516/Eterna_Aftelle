import Darwin
import Foundation
import VPReferenceCore

enum RouteInspection {
    static func run(configuration: RunConfiguration) throws {
        try configuration.validateForAudio()
        try MicrophonePermissionPlan.requireAuthorized(status: MicrophonePermissionAccess.currentStatus())
        let driver = AppleEngineDriver(material: nil)
        let configured = try ConfigurationPlan.configure(mode: configuration.mode, driver: driver)
        let route = try AudioRouteSnapshot.read(engine: driver.engine)
        let manifest = try AudioRunManifest.create(
            configuration: configuration, configured: configured, route: route, driver: driver, material: nil)
        try EngineeringFailure.check(stage: .evidenceWrite, code: .preparedWriteFailed) {
            guard configuration.outputDirectory.path.withCString({ mkdir($0, mode_t(0o700)) }) == 0 else {
                throw AudioReferenceError.evidenceWriteFailed
            }
            try manifest.writePrepared(directory: configuration.outputDirectory)
        }
        print("route_inspection=COMPLETE binding=\(route.deviceBindingStatus) engine=NOT_STARTED; no PCM")
    }
}
