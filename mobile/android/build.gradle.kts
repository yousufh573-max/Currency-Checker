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

// Some plugins (e.g. tflite_flutter) compile Java for JVM 11 but leave Kotlin
// at the Gradle JDK's default, which fails JVM-target validation. Align each
// module's Kotlin target with its own Java target.
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinJvmCompile>().configureEach {
        val javaTask = project.tasks.findByName(name.replace("Kotlin", "JavaWithJavac")) as? JavaCompile
        val target = javaTask?.targetCompatibility
        if (target != null) {
            compilerOptions.jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(target))
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
