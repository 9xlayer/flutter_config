package com.byneapp.flutter_config

import android.app.Activity
import android.content.Context
import android.content.res.Resources
import androidx.annotation.NonNull
import io.flutter.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.lang.IllegalArgumentException
import java.lang.reflect.Field

class FlutterConfigPlugin(private val context: Context? = null): FlutterPlugin, MethodCallHandler {

  private var applicationContext: Context? = context

  private lateinit var channel : MethodChannel

  override fun onAttachedToEngine(@NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    applicationContext = flutterPluginBinding.applicationContext
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_config")
    channel.setMethodCallHandler(this)
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    applicationContext = null
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    if (call.method == "loadEnvVariables") {
      val variables = loadEnvVariables()
      result.success(variables)
    } else {
      result.notImplemented()
    }
  }

  private fun loadEnvVariables(): Map<String, Any?> {
    val variables = hashMapOf<String, Any?>()

    try {
      val context = applicationContext!!.applicationContext
      val candidates = mutableListOf<String>()

      // 1. Try from string resource "build_config_package" (configured via resValue / keep.xml)
      try {
        val resId = context.resources.getIdentifier("build_config_package", "string", context.packageName)
        if (resId != 0) {
          val resPackage = context.getString(resId).trim()
          if (resPackage.isNotEmpty() && !candidates.contains(resPackage)) {
            candidates.add(resPackage)
          }
        }
      } catch (e: Resources.NotFoundException) {
        // Ignored: resource not found or stripped by shrinker
      }

      // 2. Try applicationContext.packageName (the applicationId)
      val appPackage = applicationContext?.packageName
      if (appPackage != null && !candidates.contains(appPackage)) {
        candidates.add(appPackage)
      }

      // 3. Fallback: if appPackage has a flavor suffix (e.g. com.example.app.dev),
      // try the parent namespace (com.example.app)
      if (appPackage != null && appPackage.contains(".")) {
        val parentPackage = appPackage.substringBeforeLast(".")
        if (!candidates.contains(parentPackage)) {
          candidates.add(parentPackage)
        }
      }

      // Attempt to load BuildConfig class from candidates
      var clazz: Class<*>? = null
      for (candidate in candidates) {
        try {
          clazz = Class.forName("$candidate.BuildConfig")
          break
        } catch (e: ClassNotFoundException) {
          // Continue to next candidate
        }
      }

      if (clazz == null) {
        Log.w(
          "FlutterConfig",
          "Could not access BuildConfig class for candidates: $candidates. " +
          "Ensure buildFeatures.buildConfig = true, and check proguard-rules.pro / keep.xml."
        )
        return variables
      }

      fun extractValue(f: Field): Any? {
        return try {
          f.get(null)
        } catch (e: IllegalArgumentException) {
          null
        } catch (e: IllegalAccessException) {
          null
        }
      }

      clazz.declaredFields.forEach {
        variables += it.name to extractValue(it)
      }
    } catch (e: Exception) {
      Log.w("FlutterConfig", "Error loading environment variables: ${e.message}")
    }
    return variables
  }
}
