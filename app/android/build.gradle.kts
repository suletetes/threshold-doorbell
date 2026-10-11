allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// Removed the template `subprojects { evaluationDependsOn(":app") }` block: it is
// boilerplate that forces eager configuration of :app and blocks configuration-on-demand
// (NIT-13). The Flutter plugin already wires the needed task dependencies.

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
