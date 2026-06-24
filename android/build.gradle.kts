buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("com.android.tools.build:gradle:8.1.0")
        classpath("com.google.gms:google-services:4.4.4")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.projectDirectory
        .dir("../build")

rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    // Only set the build directory for projects that are physically under the root project directory.
    // This avoids "different roots" errors when plugins are on a different drive (e.g., C: vs D:).
    if (project.projectDir.canonicalPath.startsWith(rootProject.projectDir.canonicalPath)) {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
