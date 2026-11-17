package com.zyb.opensource

import android.app.Activity
import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Bundle
import android.os.Environment
import android.provider.OpenableColumns
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private val utilityChannel = "zybapp/platform"
    private val imageRequestCode = 8120
    private var pendingImageResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "zybapp/share")
            .setMethodCallHandler { call, result ->
                if (call.method != "shareText") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val text = call.argument<String>("text").orEmpty()
                val subject = call.argument<String>("subject").orEmpty()
                val intent = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, text)
                    if (subject.isNotEmpty()) putExtra(Intent.EXTRA_SUBJECT, subject)
                }
                startActivity(Intent.createChooser(intent, "分享帖子"))
                result.success(null)
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, utilityChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickImages" -> pickImages(result)
                    "secureWrite" -> {
                        val key = call.argument<String>("key").orEmpty()
                        val value = call.argument<String>("value").orEmpty()
                        secureWrite(key, value)
                        result.success(null)
                    }
                    "secureRead" -> result.success(secureRead(call.argument<String>("key").orEmpty()))
                    "secureDelete" -> {
                        getSharedPreferences("zyb_secure", MODE_PRIVATE).edit()
                            .remove(call.argument<String>("key").orEmpty()).apply()
                        result.success(null)
                    }
                    "saveImage" -> saveImage(call.argument<String>("url").orEmpty(), result)
                    "openJdProduct" -> openJdProduct(call.argument<String>("sku").orEmpty(), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun saveImage(url: String, result: MethodChannel.Result) {
        if (url.isBlank()) {
            result.error("empty_url", "图片地址为空", null)
            return
        }
        try {
            val extension = Uri.parse(url).lastPathSegment?.substringAfterLast('.', "jpg")
                ?.takeIf { it.length in 2..5 } ?: "jpg"
            val fileName = "赚友吧_${System.currentTimeMillis()}.$extension"
            val request = DownloadManager.Request(Uri.parse(url)).apply {
                addRequestHeader("Referer", "http://www.zuanke8.com")
                addRequestHeader("User-Agent", "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 Chrome/120 Mobile Safari/537.36")
                setTitle(fileName)
                setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                setDestinationInExternalPublicDir(Environment.DIRECTORY_PICTURES, "赚友吧/$fileName")
            }
            val manager = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
            manager.enqueue(request)
            result.success(null)
        } catch (error: Exception) {
            result.error("save_failed", error.message, null)
        }
    }

    private fun openJdProduct(sku: String, result: MethodChannel.Result) {
        if (!sku.matches(Regex("\\d{6,16}"))) {
            result.error("invalid_sku", "商品编号无效", null)
            return
        }
        val appUri = "openapp.jdmobile://virtual?params=%7B%22category%22:%22jump%22,%22des%22:%22productDetail%22,%22skuId%22:%22$sku%22%7D"
        val appIntent = Intent(Intent.ACTION_VIEW, Uri.parse(appUri))
        val webIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://item.jd.com/$sku.html"))
        try {
            startActivity(appIntent)
            result.success(null)
        } catch (error: Exception) {
            try {
                startActivity(webIntent)
                result.success(null)
            } catch (fallbackError: Exception) {
                result.error("open_failed", fallbackError.message, null)
            }
        }
    }

    private fun pickImages(result: MethodChannel.Result) {
        if (pendingImageResult != null) {
            result.error("busy", "图片选择器正在使用中", null)
            return
        }
        pendingImageResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
            addCategory(Intent.CATEGORY_OPENABLE)
            type = "image/*"
            putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
        }
        startActivityForResult(intent, imageRequestCode)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != imageRequestCode) return
        val callback = pendingImageResult ?: return
        pendingImageResult = null
        if (resultCode != Activity.RESULT_OK || data == null) {
            callback.success(emptyList<String>())
            return
        }
        try {
            val uris = mutableListOf<Uri>()
            data.clipData?.let { clip ->
                for (i in 0 until clip.itemCount) uris.add(clip.getItemAt(i).uri)
            } ?: data.data?.let(uris::add)
            callback.success(uris.take(9).mapIndexed { index, uri -> copyCompressedImage(uri, index) })
        } catch (error: Exception) {
            callback.error("image_copy_failed", error.message, null)
        }
    }

    private fun copyCompressedImage(uri: Uri, index: Int): String {
        val source = contentResolver.openInputStream(uri) ?: error("无法读取图片")
        val bytes = source.use { it.readBytes() }
        val maxTargetBytes = 300 * 1024
        val output = File(cacheDir, "zyb_upload_${System.currentTimeMillis()}_$index.jpg")
        if (bytes.size <= maxTargetBytes) {
            FileOutputStream(output).use { it.write(bytes) }
            return output.absolutePath
        }

        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
        if (bitmap == null) {
            FileOutputStream(output).use { it.write(bytes) }
            return output.absolutePath
        }

        val maxSide = 1600
        val scale = minOf(1.0, maxSide.toDouble() / maxOf(bitmap.width, bitmap.height))
        var workingBitmap = if (scale < 1.0) {
            Bitmap.createScaledBitmap(
                bitmap, (bitmap.width * scale).toInt(), (bitmap.height * scale).toInt(), true
            )
        } else {
            bitmap
        }

        val stream = java.io.ByteArrayOutputStream()
        var quality = 82
        while (quality >= 25) {
            stream.reset()
            workingBitmap.compress(Bitmap.CompressFormat.JPEG, quality, stream)
            if (stream.size() <= maxTargetBytes || quality <= 25) {
                break
            }
            quality -= 10
        }

        if (stream.size() > maxTargetBytes) {
            val downScale = 0.75
            val smaller = Bitmap.createScaledBitmap(
                workingBitmap,
                (workingBitmap.width * downScale).toInt(),
                (workingBitmap.height * downScale).toInt(),
                true
            )
            stream.reset()
            smaller.compress(Bitmap.CompressFormat.JPEG, 70, stream)
            if (smaller !== workingBitmap) smaller.recycle()
        }

        FileOutputStream(output).use { it.write(stream.toByteArray()) }
        if (workingBitmap !== bitmap) workingBitmap.recycle()
        bitmap.recycle()
        return output.absolutePath
    }

    private fun secretKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("zyb_secure_key", null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance("AES", "AndroidKeyStore")
        generator.init(android.security.keystore.KeyGenParameterSpec.Builder(
            "zyb_secure_key",
            android.security.keystore.KeyProperties.PURPOSE_ENCRYPT or android.security.keystore.KeyProperties.PURPOSE_DECRYPT
        ).setBlockModes(android.security.keystore.KeyProperties.BLOCK_MODE_GCM)
            .setEncryptionPaddings(android.security.keystore.KeyProperties.ENCRYPTION_PADDING_NONE).build())
        return generator.generateKey()
    }

    private fun secureWrite(key: String, value: String) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val packed = Base64.encodeToString(cipher.iv + cipher.doFinal(value.toByteArray()), Base64.NO_WRAP)
        getSharedPreferences("zyb_secure", MODE_PRIVATE).edit().putString(key, packed).apply()
    }

    private fun secureRead(key: String): String? {
        val packed = getSharedPreferences("zyb_secure", MODE_PRIVATE).getString(key, null) ?: return null
        return try {
            val bytes = Base64.decode(packed, Base64.NO_WRAP)
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(128, bytes.copyOfRange(0, 12)))
            String(cipher.doFinal(bytes.copyOfRange(12, bytes.size)))
        } catch (_: Exception) { null }
    }
}
