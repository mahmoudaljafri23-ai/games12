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

subprojects {
    project.evaluationDependsOn(":app")
}

// Set global SDK versions for subprojects
rootProject.extra.set("compileSdkVersion", 36)
rootProject.extra.set("minSdkVersion", 24)
rootProject.extra.set("targetSdkVersion", 34)

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
