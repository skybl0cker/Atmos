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

// Force JVM 11 for all Kotlin subprojects — the home_widget plugin ships
// bytecode built for JVM 11 but defaults to compiling against 1.8.
subprojects {
    afterEvaluate {
        if (project.plugins.hasPlugin("org.jetbrains.kotlin.android")) {
            project.extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidExtension> {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
