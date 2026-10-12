//
//  File.swift
//  AppwinSupport
//
//  Created by Eliott on 04/06/2026.
//
import Foundation


protocol ConversationRepository : Sendable {
func getAll(cursor: String?, limit: Int) async throws -> CursorPaginated<Conversation>
func get(id:String) async throws -> Conversation
func create(firstMessage: String, attachments: [AttachmentInput]) async throws -> Conversation
}
