package com.clubmates.app.ui.auth

import android.Manifest
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.camera.core.*
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.mlkit.vision.MlKitAnalyzer
import androidx.camera.view.PreviewView
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.core.content.ContextCompat
import com.google.accompanist.permissions.ExperimentalPermissionsApi
import com.google.accompanist.permissions.isGranted
import com.google.accompanist.permissions.rememberPermissionState
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.clubmates.app.ui.theme.*
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

private sealed class SelfieState {
    object Intro : SelfieState()
    object TakePhoto : SelfieState()
    data class ReviewPhoto(val bitmap: Bitmap) : SelfieState()
    object LivenessCheck : SelfieState()
    object Uploading : SelfieState()
    data class Failed(val mismatchedPhotoIds: List<String> = emptyList()) : SelfieState()
}

enum class SelfieVerificationMode {
    Onboarding,
    Profile
}

@OptIn(ExperimentalPermissionsApi::class)
@Composable
fun SelfieVerificationScreen(
    mode: SelfieVerificationMode,
    onVerified: (ByteArray) -> Unit,
    onSkip: () -> Unit,
    onBack: () -> Unit
) {
    val cameraPermission = rememberPermissionState(Manifest.permission.CAMERA)
    val allowSkip = mode == SelfieVerificationMode.Onboarding

    LaunchedEffect(Unit) {
        if (!cameraPermission.status.isGranted) cameraPermission.launchPermissionRequest()
    }

    Box(modifier = Modifier.fillMaxSize().background(Background)) {
        if (mode == SelfieVerificationMode.Onboarding) {
            Column(modifier = Modifier.fillMaxSize()) {
                AuthHeader(
                    title = "ClubMates",
                    subtitle = "Verification",
                    pillCount = 4,
                    activeUpTo = 3,
                    onBack = onBack
                )

                if (cameraPermission.status.isGranted) {
                    SelfieContent(
                        onVerified = onVerified,
                        onSkip = onSkip,
                        onBack = onBack,
                        allowSkip = true,
                        topPadding = 8.dp
                    )
                } else {
                    SelfiePermissionDenied(
                        onRequest = { cameraPermission.launchPermissionRequest() },
                        onSkip = onSkip,
                        allowSkip = true
                    )
                }
            }
        } else {
            if (cameraPermission.status.isGranted) {
                SelfieContent(
                    onVerified = onVerified,
                    onSkip = onSkip,
                    onBack = onBack,
                    allowSkip = allowSkip,
                    topPadding = 64.dp
                )
            } else {
                SelfiePermissionDenied(
                    onRequest = { cameraPermission.launchPermissionRequest() },
                    onSkip = onSkip,
                    allowSkip = false
                )
            }

            ProfileVerificationBackButton(onBack = onBack)
        }
    }
}

@Composable
private fun SelfieContent(
    onVerified: (ByteArray) -> Unit,
    onSkip: () -> Unit,
    onBack: () -> Unit,
    allowSkip: Boolean,
    topPadding: Dp
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val executor = remember { Executors.newSingleThreadExecutor() }

    var selfieState by remember { mutableStateOf<SelfieState>(SelfieState.Intro) }
    var capturedJpeg by remember { mutableStateOf<ByteArray?>(null) }
    var imageCapture by remember { mutableStateOf<ImageCapture?>(null) }
    var blinkDetected by remember { mutableStateOf(false) }
    var blinkTimedOut by remember { mutableStateOf(false) }

    // Blink detection state machine
    // warmup → ready → sawClose → (fire on reopen)
    var blinkPhase by remember { mutableStateOf(0) }  // 0=warmup, 1=ready, 2=sawClose
    var openCount by remember { mutableStateOf(0) }
    var closedCount by remember { mutableStateOf(0) }
    val warmupRequired = 8
    val minClosedStreak = 2  // iOS uses 2

    // Pulsing animation for the LIVE indicator
    val infiniteTransition = rememberInfiniteTransition(label = "live")
    val liveAlpha by infiniteTransition.animateFloat(
        initialValue = 1f, targetValue = 0.25f,
        animationSpec = infiniteRepeatable(
            animation = tween(600, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "liveAlpha"
    )

    DisposableEffect(Unit) { onDispose { executor.shutdown() } }

    // ML Kit face detector configured for eye-open classification
    val faceDetectorOptions = remember {
        FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_NONE)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .setMinFaceSize(0.25f)
            .build()
    }
    val faceDetector = remember { FaceDetection.getClient(faceDetectorOptions) }
    val ctx2 = LocalContext.current

    // Intro / Failed screens shown before camera (no camera setup needed)
    when (selfieState) {
        is SelfieState.Intro -> {
            SelfieIntroScreen(
                onGetStarted = { selfieState = SelfieState.TakePhoto },
                onSkip = onSkip,
                allowSkip = allowSkip
            )
            return
        }
        is SelfieState.Failed -> {
            SelfieFailedScreen(
                mismatchedCount = (selfieState as SelfieState.Failed).mismatchedPhotoIds.size,
                onUpdatePhotos = if (allowSkip) onSkip else onBack,
                onRetry = {
                    blinkPhase = 0; openCount = 0; closedCount = 0
                    blinkDetected = false; blinkTimedOut = false
                    selfieState = SelfieState.TakePhoto
                }
            )
            return
        }
        else -> Unit
    }

    Column(modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp)
                .padding(top = topPadding, bottom = 16.dp),
            verticalArrangement = Arrangement.spacedBy(20.dp)
        ) {
            // Step tracker (mirrors iOS step dots: 1 Take Photo → 2 Blink)
            SelfieStepTracker(currentState = selfieState, blinkDetected = blinkDetected)

            // Instructions card — content changes per step
            InstructionsCard(state = selfieState)

            // Camera preview / captured photo area
            val borderColor = when {
                blinkDetected -> Like
                selfieState is SelfieState.LivenessCheck -> authPink
                selfieState is SelfieState.ReviewPhoto -> Like
                else -> Surface
            }

            Box(
                modifier = Modifier
                    .fillMaxWidth()
                    .height(360.dp)
                    .clip(RoundedCornerShape(28.dp))
                    .background(Color.Black)
                    .border(2.dp, borderColor, RoundedCornerShape(28.dp))
            ) {
                when (val state = selfieState) {
                    is SelfieState.ReviewPhoto -> {
                        // Show captured photo for review
                        androidx.compose.foundation.Image(
                            bitmap = state.bitmap.asImageBitmap(),
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                    else -> {
                        // Live camera feed
                        AndroidView(
                            factory = { ctx ->
                                PreviewView(ctx).also { pv ->
                                    val future = ProcessCameraProvider.getInstance(ctx)
                                    future.addListener({
                                        val provider = future.get()
                                        val preview = Preview.Builder().build()
                                            .also { it.setSurfaceProvider(pv.surfaceProvider) }

                                        val ic = ImageCapture.Builder()
                                            .setCaptureMode(ImageCapture.CAPTURE_MODE_MINIMIZE_LATENCY)
                                            .build()
                                        imageCapture = ic

                                        val analyzer = MlKitAnalyzer(
                                            listOf(faceDetector),
                                            ImageAnalysis.COORDINATE_SYSTEM_ORIGINAL,
                                            ContextCompat.getMainExecutor(ctx)
                                        ) { result ->
                                            if (selfieState !is SelfieState.LivenessCheck || blinkDetected) return@MlKitAnalyzer
                                            val faces = result.getValue(faceDetector) ?: return@MlKitAnalyzer
                                            val face = faces.firstOrNull() ?: return@MlKitAnalyzer
                                            val leftOpen = face.leftEyeOpenProbability ?: return@MlKitAnalyzer
                                            val rightOpen = face.rightEyeOpenProbability ?: return@MlKitAnalyzer
                                            val bothOpen = leftOpen > 0.5f && rightOpen > 0.5f
                                            when (blinkPhase) {
                                                0 -> { // warmup
                                                    if (bothOpen) {
                                                        openCount++
                                                        if (openCount >= warmupRequired) blinkPhase = 1
                                                    } else {
                                                        openCount = 0
                                                    }
                                                }
                                                1 -> { // ready
                                                    if (!bothOpen) {
                                                        blinkPhase = 2
                                                        closedCount = 1
                                                    }
                                                }
                                                2 -> { // sawClose
                                                    if (!bothOpen) {
                                                        closedCount++
                                                    } else {
                                                        val streak = closedCount
                                                        closedCount = 0
                                                        if (streak >= minClosedStreak) {
                                                            blinkDetected = true
                                                        } else {
                                                            blinkPhase = 1 // flicker, back to ready
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                        val imageAnalysis = ImageAnalysis.Builder().build()
                                            .also { it.setAnalyzer(executor, analyzer) }

                                        try {
                                            provider.unbindAll()
                                            provider.bindToLifecycle(
                                                lifecycleOwner,
                                                CameraSelector.DEFAULT_FRONT_CAMERA,
                                                preview, ic, imageAnalysis
                                            )
                                        } catch (e: Exception) {
                                            provider.bindToLifecycle(
                                                lifecycleOwner,
                                                CameraSelector.DEFAULT_BACK_CAMERA,
                                                preview, ic, imageAnalysis
                                            )
                                        }
                                    }, ContextCompat.getMainExecutor(ctx))
                                }
                            },
                            modifier = Modifier.fillMaxSize()
                        )

                        // Face oval guide
                        if (!blinkDetected) {
                            FaceOvalGuide(
                                tinted = selfieState is SelfieState.LivenessCheck,
                                modifier = Modifier.align(Alignment.Center)
                            )
                        }

                        // LIVE indicator during liveness check
                        if (selfieState is SelfieState.LivenessCheck && !blinkDetected) {
                            Row(
                                modifier = Modifier
                                    .align(Alignment.TopEnd)
                                    .padding(14.dp)
                                    .background(Color.Black.copy(alpha = 0.65f), RoundedCornerShape(50))
                                    .padding(horizontal = 10.dp, vertical = 7.dp),
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.spacedBy(6.dp)
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(8.dp)
                                        .background(authPink.copy(alpha = liveAlpha), CircleShape)
                                )
                                Text(
                                    "LIVE",
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = Color.White,
                                    letterSpacing = 1.sp
                                )
                            }
                        }

                        // Idle hint
                        if (selfieState is SelfieState.TakePhoto) {
                            Box(
                                modifier = Modifier
                                    .align(Alignment.BottomCenter)
                                    .padding(bottom = 20.dp)
                                    .background(Color.Black.copy(alpha = 0.55f), RoundedCornerShape(50))
                                    .padding(horizontal = 16.dp, vertical = 8.dp)
                            ) {
                                Text(
                                    "Tap below to take your selfie",
                                    fontSize = 13.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = Color.White.copy(alpha = 0.85f)
                                )
                            }
                        }
                    }
                }

                // Blink success overlay
                androidx.compose.animation.AnimatedVisibility(
                    visible = blinkDetected,
                    enter = fadeIn() + scaleIn(initialScale = 0.85f),
                    modifier = Modifier.fillMaxSize()
                ) {
                    Box(
                        modifier = Modifier
                            .fillMaxSize()
                            .background(Color.Black.copy(alpha = 0.5f)),
                        contentAlignment = Alignment.Center
                    ) {
                        Column(
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(12.dp)
                        ) {
                            Icon(
                                Icons.Default.CheckCircle,
                                contentDescription = null,
                                tint = Like,
                                modifier = Modifier.size(64.dp)
                            )
                            Text(
                                "Blink Detected!",
                                fontSize = 22.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                        }
                    }
                }
            }

            // Liveness prompt card
            AnimatedVisibility(
                visible = selfieState is SelfieState.LivenessCheck && !blinkDetected,
                enter = slideInVertically(initialOffsetY = { it }) + fadeIn()
            ) {
                BlinkPromptCard()
            }

            // Retake link shown during review
            if (selfieState is SelfieState.ReviewPhoto) {
                Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    TextButton(onClick = {
                        selfieState = SelfieState.TakePhoto
                        capturedJpeg = null
                    }) {
                        Icon(
                            Icons.Default.Refresh,
                            contentDescription = null,
                            modifier = Modifier.size(16.dp),
                            tint = TextHint
                        )
                        Spacer(Modifier.width(4.dp))
                        Text("Retake Photo", fontSize = 13.sp, color = TextHint)
                    }
                }
            }

            // Skip link
            if (allowSkip && selfieState is SelfieState.TakePhoto) {
                Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                    TextButton(onClick = onSkip) {
                        Text("Skip for now", fontSize = 13.sp, color = TextHint)
                    }
                }
            }
        }

        // Bottom action bar
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .background(Background)
                .padding(horizontal = 20.dp)
                .padding(top = 8.dp, bottom = 20.dp)
        ) {
            when {
                selfieState is SelfieState.TakePhoto -> {
                    // Camera shutter button
                    Box(modifier = Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
                        Box(
                            modifier = Modifier
                                .size(80.dp)
                                .background(Color.Transparent, CircleShape)
                                .border(3.dp, authPink, CircleShape),
                            contentAlignment = Alignment.Center
                        ) {
                            Button(
                                onClick = {
                                    val ic = imageCapture ?: return@Button
                                    ic.takePicture(executor, object : ImageCapture.OnImageCapturedCallback() {
                                        override fun onCaptureSuccess(image: ImageProxy) {
                                            val buffer = image.planes[0].buffer
                                            val bytes = ByteArray(buffer.remaining()).also { buffer.get(it) }
                                            // Mirror front camera horizontally
                                            val raw = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
                                            val matrix = Matrix().apply { preScale(-1f, 1f) }
                                            val mirrored = Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height, matrix, true)
                                            val stream = ByteArrayOutputStream()
                                            mirrored.compress(Bitmap.CompressFormat.JPEG, 85, stream)
                                            val jpeg = stream.toByteArray()
                                            image.close()
                                            // Jump back to main thread
                                            ContextCompat.getMainExecutor(context).execute {
                                                capturedJpeg = jpeg
                                                selfieState = SelfieState.ReviewPhoto(mirrored)
                                            }
                                        }
                                        override fun onError(exc: ImageCaptureException) {
                                        }
                                    })
                                },
                                modifier = Modifier.size(64.dp),
                                shape = CircleShape,
                                colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
                                contentPadding = PaddingValues(0.dp)
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(64.dp)
                                        .background(authGradient, CircleShape),
                                    contentAlignment = Alignment.Center
                                ) {
                                    Icon(
                                        Icons.Default.CameraAlt,
                                        contentDescription = "Take Selfie",
                                        tint = Color.White,
                                        modifier = Modifier.size(28.dp)
                                    )
                                }
                            }
                        }
                    }
                }

                selfieState is SelfieState.ReviewPhoto && !blinkDetected -> {
                    SelfieActionButton(
                        label = "Looks Good — Continue",
                        icon = Icons.Default.ArrowForward,
                        gradient = authGradient,
                        enabled = true,
                        onClick = {
                            blinkPhase = 0
                            openCount = 0
                            closedCount = 0
                            blinkDetected = false
                            blinkTimedOut = false
                            selfieState = SelfieState.LivenessCheck
                        }
                    )
                }

                selfieState is SelfieState.LivenessCheck && !blinkDetected -> {
                    // 15-second timeout — mirrors iOS blinkTimeoutTask 15_000_000_000ns
                    LaunchedEffect(selfieState) {
                        blinkTimedOut = false
                        kotlinx.coroutines.delay(15_000)
                        if (!blinkDetected) blinkTimedOut = true
                    }

                    if (blinkTimedOut) {
                        Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(
                                "Try better lighting or hold your face steady.",
                                fontSize = 12.sp, color = TextSecondary,
                                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                                modifier = Modifier.fillMaxWidth()
                            )
                            SelfieActionButton(
                                label = "Retry Blink Detection",
                                icon = Icons.Default.Refresh,
                                gradient = authGradient,
                                enabled = true,
                                onClick = {
                                    blinkPhase = 0
                                    openCount = 0
                                    closedCount = 0
                                    blinkTimedOut = false
                                }
                            )
                        }
                    } else {
                        SelfieActionButton(
                            label = "Waiting for blink...",
                            icon = Icons.Default.Visibility,
                            gradient = Brush.linearGradient(listOf(SurfaceVariant, SurfaceVariant)),
                            enabled = false,
                            onClick = {}
                        )
                    }
                }

                blinkDetected -> {
                    // Auto-advance: show uploading briefly then call onVerified
                    LaunchedEffect(Unit) {
                        selfieState = SelfieState.Uploading
                        kotlinx.coroutines.delay(800)
                        onVerified(capturedJpeg ?: ByteArray(0))
                    }
                    SelfieActionButton(
                        label = "Verifying...",
                        icon = Icons.Default.HourglassTop,
                        gradient = Brush.linearGradient(listOf(SurfaceVariant, SurfaceVariant)),
                        enabled = false,
                        onClick = {}
                    )
                }

                else -> {}
            }
        }
    }
}

@Composable
private fun InstructionsCard(state: SelfieState) {
    val isLiveness = state is SelfieState.LivenessCheck
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(CardBackground, RoundedCornerShape(24.dp))
            .padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.Top
        ) {
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .background(authPink.copy(alpha = 0.15f), CircleShape),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    if (isLiveness) Icons.Default.Visibility else Icons.Default.Shield,
                    contentDescription = null,
                    tint = authPink,
                    modifier = Modifier.size(18.dp)
                )
            }
            Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text(
                    if (isLiveness) "Liveness Check" else "Quick Selfie Verification",
                    fontSize = 15.sp,
                    fontWeight = FontWeight.SemiBold,
                    color = TextPrimary
                )
                Text(
                    if (isLiveness)
                        "Now blink your eyes once to confirm you're live."
                    else
                        "Take a clear selfie so other members know you're real. This is never shared publicly.",
                    fontSize = 13.sp,
                    color = TextSecondary,
                    lineHeight = 18.sp
                )
            }
        }

        HorizontalDivider(color = Surface)

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceEvenly
        ) {
            if (isLiveness) {
                TipItem(icon = Icons.Default.Visibility, text = "Look ahead", tint = authPink)
                TipItem(icon = Icons.Default.FlashOn, text = "Blink once", tint = authPurple)
                TipItem(icon = Icons.Default.FaceRetouchingNatural, text = "Stay still", tint = Color(0xFF00E5A0))
            } else {
                TipItem(icon = Icons.Default.WbSunny, text = "Good lighting", tint = Color(0xFFFFC107))
                TipItem(icon = Icons.Default.FaceRetouchingNatural, text = "Face forward", tint = authPink)
                TipItem(icon = Icons.Default.FlipCameraAndroid, text = "Front camera", tint = authPurple)
            }
        }
    }
}

@Composable
private fun BlinkPromptCard() {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(CardBackground, RoundedCornerShape(20.dp))
            .padding(18.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp)
    ) {
        Box(
            modifier = Modifier
                .size(48.dp)
                .background(authPink.copy(alpha = 0.15f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Default.Visibility, contentDescription = null, tint = authPink, modifier = Modifier.size(24.dp))
        }
        Column(modifier = Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text("Blink to confirm", fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            Text("Keep your face in the oval and blink once.", fontSize = 13.sp, color = TextSecondary)
        }
        Icon(Icons.Default.GraphicEq, contentDescription = null, tint = authPink, modifier = Modifier.size(24.dp))
    }
}

@Composable
private fun FaceOvalGuide(tinted: Boolean, modifier: Modifier = Modifier) {
    val color = if (tinted) authPink else Color.White.copy(alpha = 0.35f)
    Box(
        modifier = modifier
            .size(width = 160.dp, height = 210.dp)
            .border(2.dp, color, RoundedCornerShape(percent = 50))
    )
}

@Composable
private fun SelfieActionButton(
    label: String,
    icon: ImageVector,
    gradient: Brush,
    enabled: Boolean,
    onClick: () -> Unit
) {
    Button(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.fillMaxWidth().height(52.dp),
        shape = RoundedCornerShape(22.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Color.Transparent,
            disabledContainerColor = Color.Transparent
        ),
        contentPadding = PaddingValues(0.dp)
    ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(gradient, RoundedCornerShape(22.dp)),
            contentAlignment = Alignment.Center
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(10.dp)
            ) {
                Icon(icon, contentDescription = null, tint = Color.White, modifier = Modifier.size(20.dp))
                Text(label, fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
            }
        }
    }
}

@Composable
private fun TipItem(icon: ImageVector, text: String, tint: Color) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(8.dp),
        modifier = Modifier.width(88.dp)
    ) {
        Box(
            modifier = Modifier
                .size(40.dp)
                .background(tint.copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
        }
        Text(
            text,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            color = TextSecondary,
            textAlign = TextAlign.Center
        )
    }
}

@Composable
private fun SelfiePermissionDenied(onRequest: () -> Unit, onSkip: () -> Unit, allowSkip: Boolean) {
    Column(
        modifier = Modifier.fillMaxSize().padding(32.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(
            modifier = Modifier
                .size(72.dp)
                .background(authPink.copy(alpha = 0.12f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            Icon(Icons.Default.CameraAlt, contentDescription = null, tint = authPink, modifier = Modifier.size(32.dp))
        }
        Spacer(modifier = Modifier.height(20.dp))
        Text(
            "Camera Access Required",
            fontSize = 18.sp,
            fontWeight = FontWeight.SemiBold,
            color = TextPrimary,
            textAlign = TextAlign.Center
        )
        Spacer(modifier = Modifier.height(10.dp))
        Text(
            "Please allow camera access to complete selfie verification.",
            fontSize = 13.sp,
            color = TextSecondary,
            textAlign = TextAlign.Center,
            lineHeight = 20.sp
        )
        Spacer(modifier = Modifier.height(32.dp))
        Button(
            onClick = onRequest,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = RoundedCornerShape(22.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
            contentPadding = PaddingValues(0.dp)
        ) {
            Box(
                modifier = Modifier.fillMaxSize().background(authGradient, RoundedCornerShape(22.dp)),
                contentAlignment = Alignment.Center
            ) {
                Text("Grant Access", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
            }
        }
        Spacer(modifier = Modifier.height(12.dp))
        if (allowSkip) {
            TextButton(onClick = onSkip) {
                Text("Skip for now", color = TextHint)
            }
        }
    }
}

// ── Intro screen (mirrors iOS .intro VerificationStep) ───────────────────────

@Composable
private fun SelfieIntroScreen(onGetStarted: () -> Unit, onSkip: () -> Unit, allowSkip: Boolean) {
    val pink = Color(0xFFFF6B9D)
    val purple = Color(0xFFC44EFF)

    Column(
        modifier = Modifier.fillMaxSize().background(Background)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 24.dp).padding(top = 32.dp, bottom = 40.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(32.dp)
    ) {
        // Hero icon
        Box(contentAlignment = Alignment.Center) {
            Box(modifier = Modifier.size(140.dp).background(pink.copy(0.06f), CircleShape))
            Box(modifier = Modifier.size(100.dp).background(pink.copy(0.10f), CircleShape))
            Icon(Icons.Default.Face, null, tint = pink, modifier = Modifier.size(52.dp))
        }

        Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text("Verify Your Identity", fontSize = 26.sp, fontWeight = FontWeight.Bold, color = TextPrimary, textAlign = TextAlign.Center)
            Text(
                "A quick selfie confirms you're the person in your profile photos.",
                fontSize = 15.sp, color = TextSecondary, textAlign = TextAlign.Center, lineHeight = 22.sp
            )
        }

        // Checklist card
        Column(
            modifier = Modifier.fillMaxWidth()
                .background(CardBackground, RoundedCornerShape(20.dp))
                .border(1.dp, Color.White.copy(0.06f), RoundedCornerShape(20.dp))
                .padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            IntroCheckRow(Icons.Default.WbSunny, Color(0xFFFFB800), "Good lighting", "Face a window or bright light source")
            IntroCheckRow(Icons.Default.Face, pink, "Face the camera directly", "Remove glasses or hats if you can")
            IntroCheckRow(Icons.Default.Visibility, purple, "Be ready to blink", "You'll be asked to blink once to prove you're live")
        }

        Column(verticalArrangement = Arrangement.spacedBy(12.dp), modifier = Modifier.fillMaxWidth()) {
            Button(
                onClick = onGetStarted,
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(18.dp),
                colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
                contentPadding = PaddingValues(0.dp)
            ) {
                Box(
                    modifier = Modifier.fillMaxSize()
                        .background(Brush.linearGradient(listOf(pink, purple)), RoundedCornerShape(18.dp)),
                    contentAlignment = Alignment.Center
                ) {
                    Text("Get Started", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
                }
            }
            if (allowSkip) {
                TextButton(onClick = onSkip, modifier = Modifier.fillMaxWidth()) {
                    Text("Skip for now", color = TextHint)
                }
            }
        }
    }
}

@Composable
private fun ProfileVerificationBackButton(onBack: () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(horizontal = 20.dp, vertical = 12.dp)
    ) {
        IconButton(
            onClick = onBack,
            modifier = Modifier
                .size(42.dp)
                .background(Surface.copy(alpha = 0.95f), CircleShape)
        ) {
            Icon(
                Icons.Default.ArrowBack,
                contentDescription = "Back",
                tint = TextPrimary
            )
        }
    }
}

@Composable
private fun IntroCheckRow(icon: ImageVector, color: Color, title: String, subtitle: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(14.dp)) {
        Box(modifier = Modifier.size(38.dp).background(color.copy(0.12f), CircleShape), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = color, modifier = Modifier.size(18.dp))
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(title, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = TextPrimary)
            Text(subtitle, fontSize = 12.sp, color = TextSecondary)
        }
    }
}

// ── Failed screen (mirrors iOS .failed VerificationStep) ─────────────────────

@Composable
private fun SelfieFailedScreen(mismatchedCount: Int, onUpdatePhotos: () -> Unit, onRetry: () -> Unit) {
    val pink = Color(0xFFFF6B9D)
    val purple = Color(0xFFC44EFF)

    Column(
        modifier = Modifier.fillMaxSize().background(Background).padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Box(modifier = Modifier.size(72.dp).background(pink.copy(0.12f), CircleShape), contentAlignment = Alignment.Center) {
            Icon(Icons.Default.Warning, null, tint = pink, modifier = Modifier.size(36.dp))
        }
        Spacer(Modifier.height(20.dp))
        Text("Photos Don't Match", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = TextPrimary, textAlign = TextAlign.Center)
        Spacer(Modifier.height(10.dp))
        Text(
            if (mismatchedCount > 0) "$mismatchedCount photo(s) appear to show a different person."
            else "Ensure your profile photos clearly show your face.",
            fontSize = 14.sp, color = TextSecondary, textAlign = TextAlign.Center, lineHeight = 20.sp
        )
        Spacer(Modifier.height(32.dp))
        Button(
            onClick = onUpdatePhotos,
            modifier = Modifier.fillMaxWidth().height(52.dp),
            shape = RoundedCornerShape(18.dp),
            colors = ButtonDefaults.buttonColors(containerColor = Color.Transparent),
            contentPadding = PaddingValues(0.dp)
        ) {
            Box(
                modifier = Modifier.fillMaxSize()
                    .background(Brush.linearGradient(listOf(pink, purple)), RoundedCornerShape(18.dp)),
                contentAlignment = Alignment.Center
            ) {
                Text("Update Photos", fontSize = 16.sp, fontWeight = FontWeight.SemiBold, color = Color.White)
            }
        }
        Spacer(Modifier.height(12.dp))
        TextButton(onClick = onRetry, modifier = Modifier.fillMaxWidth()) {
            Text("Try Again", color = TextSecondary)
        }
    }
}

// ── Step tracker (mirrors iOS step dots: 1 Take Photo → 2 Blink) ─────────────

@Composable
private fun SelfieStepTracker(currentState: SelfieState, blinkDetected: Boolean) {
    val pink = Color(0xFFFF6B9D)
    val purple = Color(0xFFC44EFF)
    val isDoneWithStep1 = currentState !is SelfieState.TakePhoto && currentState !is SelfieState.ReviewPhoto
    val dot1Active = currentState is SelfieState.TakePhoto || currentState is SelfieState.ReviewPhoto
    val dot2Done = blinkDetected

    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center
    ) {
        StepDot(number = "1", label = "Take Photo", active = dot1Active, done = isDoneWithStep1, pink = pink)
        Box(
            modifier = Modifier.width(48.dp).height(2.dp)
                .background(if (isDoneWithStep1) Brush.linearGradient(listOf(pink, purple)) else Brush.linearGradient(listOf(Surface, Surface)))
        )
        StepDot(number = "2", label = "Blink", active = currentState is SelfieState.LivenessCheck, done = dot2Done, pink = pink)
    }
}

@Composable
private fun StepDot(number: String, label: String, active: Boolean, done: Boolean, pink: Color) {
    val purple = Color(0xFFC44EFF)
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(
            modifier = Modifier.size(28.dp).background(
                if (done || active) Brush.linearGradient(listOf(pink, purple)) else Brush.linearGradient(listOf(Surface, Surface)),
                CircleShape
            ).border(1.dp, if (active || done) Color.Transparent else TextHint.copy(0.3f), CircleShape),
            contentAlignment = Alignment.Center
        ) {
            if (done) Icon(Icons.Default.Check, null, tint = Color.White, modifier = Modifier.size(14.dp))
            else Text(number, fontSize = 12.sp, fontWeight = FontWeight.Bold, color = if (active) Color.White else TextHint)
        }
        Text(label, fontSize = 10.sp, fontWeight = FontWeight.Medium, color = if (active || done) TextPrimary else TextHint)
    }
}
