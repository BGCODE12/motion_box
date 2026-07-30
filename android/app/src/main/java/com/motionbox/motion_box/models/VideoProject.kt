package com.motionbox.motion_box.models

import android.net.Uri
import java.io.Serializable

data class VideoProject(
    val sourceUri: Uri,
    val sourceName: String,
    val operations: List<EditOperation> = emptyList(),
    val createdAt: Long = System.currentTimeMillis(),
    val lastModifiedAt: Long = System.currentTimeMillis()
) : Serializable {

    fun getDurationAfterTrims(): Long? {
        var effectiveDuration: Long? = null
        for (operation in operations) {
            if (operation is EditOperation.Trim) {
                effectiveDuration = operation.endMs - operation.startMs
            }
        }
        return effectiveDuration
    }

    fun addOperation(operation: EditOperation): VideoProject {
        return copy(
            operations = operations + operation,
            lastModifiedAt = System.currentTimeMillis()
        )
    }

    fun undoLastOperation(): VideoProject? {
        if (operations.isEmpty()) return null
        return copy(
            operations = operations.dropLast(1),
            lastModifiedAt = System.currentTimeMillis()
        )
    }

    fun hasOperations(): Boolean = operations.isNotEmpty()
    fun getOperationCount(): Int = operations.size
}

data class EditRecipe(
    val projectName: String,
    val sourceUri: Uri,
    val sourceName: String,
    val operations: List<EditOperation> = emptyList(),
    val createdAt: Long = System.currentTimeMillis(),
    val lastModifiedAt: Long = System.currentTimeMillis()
) : Serializable {

    fun toVideoProject(): VideoProject {
        return VideoProject(
            sourceUri = sourceUri,
            sourceName = sourceName,
            operations = operations,
            createdAt = createdAt,
            lastModifiedAt = lastModifiedAt
        )
    }

    companion object {
        fun fromVideoProject(projectName: String, project: VideoProject): EditRecipe {
            return EditRecipe(
                projectName = projectName,
                sourceUri = project.sourceUri,
                sourceName = project.sourceName,
                operations = project.operations,
                createdAt = project.createdAt,
                lastModifiedAt = project.lastModifiedAt
            )
        }
    }
}
