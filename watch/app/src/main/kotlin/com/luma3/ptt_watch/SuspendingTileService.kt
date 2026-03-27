package com.luma3.ptt_watch

import androidx.concurrent.futures.CallbackToFutureAdapter
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.ResourceBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

abstract class SuspendingTileService : TileService() {
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    final override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest
    ): ListenableFuture<TileBuilders.Tile> {
        return CallbackToFutureAdapter.getFuture { completer ->
            serviceScope.launch {
                runCatching { onTileRequestSuspending(requestParams) }
                    .onSuccess { completer.set(it) }
                    .onFailure { completer.setException(it) }
            }
            "tile_request"
        }
    }

    final override fun onResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest
    ): ListenableFuture<ResourceBuilders.Resources> {
        return CallbackToFutureAdapter.getFuture { completer ->
            serviceScope.launch {
                runCatching { onResourcesRequestSuspending(requestParams) }
                    .onSuccess { completer.set(it) }
                    .onFailure { completer.setException(it) }
            }
            "resources_request"
        }
    }

    override fun onDestroy() {
        serviceScope.cancel()
        super.onDestroy()
    }

    protected abstract suspend fun onTileRequestSuspending(
        requestParams: RequestBuilders.TileRequest
    ): TileBuilders.Tile

    protected open suspend fun onResourcesRequestSuspending(
        requestParams: RequestBuilders.ResourcesRequest
    ): ResourceBuilders.Resources {
        return ResourceBuilders.Resources.Builder().setVersion("1").build()
    }
}
