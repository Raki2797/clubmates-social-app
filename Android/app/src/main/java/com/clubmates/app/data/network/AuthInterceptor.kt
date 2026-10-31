package com.clubmates.app.data.network

import com.clubmates.app.data.local.TokenStore
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.Authenticator
import okhttp3.Interceptor
import okhttp3.Request
import okhttp3.Response
import okhttp3.Route
import javax.inject.Inject
import javax.inject.Provider
import javax.inject.Singleton

@Singleton
class AuthInterceptor @Inject constructor(private val tokenStore: TokenStore) : Interceptor {
    override fun intercept(chain: Interceptor.Chain): Response {
        val token = tokenStore.accessToken
        val request = if (token != null) {
            chain.request().newBuilder()
                .header("Authorization", "Bearer $token")
                .build()
        } else {
            chain.request()
        }
        return chain.proceed(request)
    }
}

@Singleton
class TokenAuthenticator @Inject constructor(
    private val tokenStore: TokenStore,
    // Provider to avoid circular dependency with ApiService
    private val apiServiceProvider: Provider<ApiService>
) : Authenticator {

    private val refreshMutex = Mutex()

    override fun authenticate(route: Route?, response: Response): Request? {
        if (response.code != 401) return null
        // Only retry once
        if (response.request.header("X-Retry-Auth") != null) return null

        val refreshToken = tokenStore.refreshToken ?: return null

        val newTokens = runBlocking {
            // Mutex ensures only one refresh runs at a time.
            // If another coroutine already refreshed while we were waiting,
            // check if the token changed and reuse it instead of refreshing again.
            refreshMutex.withLock {
                val currentToken = tokenStore.accessToken
                val requestToken = response.request.header("Authorization")
                    ?.removePrefix("Bearer ")?.trim()

                // Token already refreshed by a concurrent request — reuse it
                if (currentToken != null && currentToken != requestToken) {
                    return@withLock AuthResponse(
                        accessToken = currentToken,
                        refreshToken = tokenStore.refreshToken ?: "",
                        user = AuthUser("", "", false)
                    )
                }

                runCatching {
                    apiServiceProvider.get().refresh(RefreshRequest(refreshToken))
                }.getOrNull()
            }
        } ?: return null

        tokenStore.accessToken = newTokens.accessToken
        tokenStore.refreshToken = newTokens.refreshToken

        return response.request.newBuilder()
            .header("Authorization", "Bearer ${newTokens.accessToken}")
            .header("X-Retry-Auth", "true")
            .build()
    }
}
