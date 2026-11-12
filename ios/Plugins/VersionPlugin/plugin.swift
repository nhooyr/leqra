import PackagePlugin

@main
struct VersionPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) throws -> [Command] {
        let root = context.package.directory.removingLastComponent()
        let generator = root.appending("scripts/ios-version.sh")
        let output = context.pluginWorkDirectory.appending("GeneratedVersion.swift")
        return [.buildCommand(
            displayName: "Generate leqra release version",
            executable: Path("/bin/sh"),
            arguments: [generator.string, "--swift", output.string],
            inputFiles: [generator, root.appending("scripts/version.sh"), root.appending("src/main.go")],
            outputFiles: [output]
        )]
    }
}
