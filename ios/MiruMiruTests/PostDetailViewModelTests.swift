import XCTest
@testable import MiruMiru

@MainActor
final class PostDetailViewModelTests: XCTestCase {
    func testToggleLikeUpdatesDetailAndSyncStoreImmediately() async {
        let client = MockBoardsClient()
        let store = BoardsSyncStore()
        let detail = PostDetailContent(
            postId: 100,
            boardId: 101,
            boardCode: "free",
            boardName: "Free Board",
            title: "Anyone free to study?",
            content: "Let's meet at the library.",
            authorMemberId: 7,
            authorDisplayName: "Anonymous",
            isAnonymous: true,
            isMine: false,
            isLikedByMe: false,
            likeCount: 4,
            commentCount: 1,
            comments: [],
            images: [],
            createdAt: "2026-03-24T00:00:00.000Z",
            updatedAt: "2026-03-24T00:00:00.000Z"
        )
        let hotPost = HotPostSummary(
            id: 100,
            boardId: 101,
            boardCode: "free",
            boardName: "Free Board",
            title: detail.title,
            authorDisplayName: detail.authorDisplayName,
            isAnonymous: detail.isAnonymous,
            likeCount: 4,
            commentCount: 1,
            createdAt: detail.createdAt
        )
        let refreshedHotPost = HotPostSummary(
            id: hotPost.id,
            boardId: hotPost.boardId,
            boardCode: hotPost.boardCode,
            boardName: hotPost.boardName,
            title: hotPost.title,
            authorDisplayName: hotPost.authorDisplayName,
            isAnonymous: hotPost.isAnonymous,
            likeCount: 5,
            commentCount: hotPost.commentCount,
            createdAt: hotPost.createdAt
        )

        client.postDetailResult = .success(detail)
        client.hotPostsResult = .success([refreshedHotPost])
        store.ingestHotPosts([hotPost])

        let viewModel = PostDetailViewModel(client: client, syncStore: store, postId: detail.postId)

        await viewModel.loadIfNeeded()
        await viewModel.toggleLike()
        await Task.yield()

        guard case let .loaded(updatedDetail) = viewModel.state else {
            return XCTFail("Expected loaded detail state")
        }

        XCTAssertTrue(updatedDetail.isLikedByMe)
        XCTAssertEqual(updatedDetail.likeCount, 5)
        XCTAssertEqual(store.projectHotPosts([hotPost]).first?.likeCount, 5)
        XCTAssertEqual(client.likedPostIds, [detail.postId])
    }

    func testDeletePostMarksDismissAndRemovesPostFromProjectedLists() async {
        let client = MockBoardsClient()
        let store = BoardsSyncStore()
        let detail = PostDetailContent(
            postId: 200,
            boardId: 101,
            boardCode: "free",
            boardName: "Free Board",
            title: "Delete me",
            content: "Temporary post",
            authorMemberId: 8,
            authorDisplayName: "Anonymous",
            isAnonymous: true,
            isMine: true,
            isLikedByMe: false,
            likeCount: 2,
            commentCount: 0,
            comments: [],
            images: [],
            createdAt: "2026-03-24T00:00:00.000Z",
            updatedAt: "2026-03-24T00:00:00.000Z"
        )
        let hotPost = HotPostSummary(
            id: 200,
            boardId: 101,
            boardCode: "free",
            boardName: "Free Board",
            title: detail.title,
            authorDisplayName: detail.authorDisplayName,
            isAnonymous: detail.isAnonymous,
            likeCount: 2,
            commentCount: 0,
            createdAt: detail.createdAt
        )
        let boardPost = BoardPostSummary(
            id: 200,
            title: detail.title,
            authorDisplayName: detail.authorDisplayName,
            isAnonymous: detail.isAnonymous,
            likeCount: 2,
            commentCount: 0,
            createdAt: detail.createdAt
        )

        client.postDetailResult = .success(detail)
        client.hotPostsResult = .success([])
        store.ingestHotPosts([hotPost])

        let viewModel = PostDetailViewModel(client: client, syncStore: store, postId: detail.postId)

        await viewModel.loadIfNeeded()
        await viewModel.deletePost()
        await Task.yield()

        XCTAssertTrue(viewModel.didDeletePost)
        XCTAssertTrue(store.projectHotPosts([hotPost]).isEmpty)
        XCTAssertTrue(store.projectBoardPosts([boardPost]).isEmpty)
        XCTAssertEqual(client.deletedPostIds, [detail.postId])
    }
}

@MainActor
final class MessagesInboxViewModelTests: XCTestCase {
    func testStartChatPassesExplicitPartnerMemberId() async {
        let client = MockMessagesClient()
        let realtimeClient = MockMessagesRealtimeClient()
        let viewModel = MessagesInboxViewModel(client: client, realtimeClient: realtimeClient)

        client.viewerResult = .success(MessagesViewer(memberId: 1, displayName: "Tester"))
        client.createRoomResult = .success(
            MessageRoomCreated(
                roomId: 101,
                postId: 2001,
                member1Id: 1,
                member2Id: 22,
                roomTitle: "Study Post",
                counterpartDisplayName: "Anonymous 2",
                isAnonMe: false,
                isAnonOther: true,
                created: true
            )
        )
        client.roomsResult = .success([])

        let context = await viewModel.startChat(
            using: MessageStartRequest(
                postId: 2001,
                postTitle: "Study Post",
                postIsAnonymous: true,
                partnerMemberId: 22,
                targetDisplayName: "Anonymous 2",
                targetIsAnonymous: true,
                requesterIsAnonymous: false
            )
        )

        XCTAssertEqual(client.lastCreateRoomRequest?.postId, 2001)
        XCTAssertEqual(client.lastCreateRoomRequest?.partnerMemberId, 22)
        XCTAssertEqual(context?.otherMemberId, 22)
    }
}

@MainActor
final class ChatRoomViewModelTests: XCTestCase {
    func testBlockCounterpartDisablesComposerAndPreventsSend() async {
        let client = MockMessagesClient()
        let realtimeClient = MockMessagesRealtimeClient()
        let viewModel = ChatRoomViewModel(
            context: MessageRoomContext(
                roomId: 88,
                postId: 2001,
                postTitle: "Study Post",
                roomTitle: "Study Post",
                otherMemberId: 22,
                counterpartDisplayName: "Anonymous 2",
                isAnonMe: false,
                isAnonOther: true,
                myLastReadMessageId: nil,
                otherLastReadMessageId: nil
            ),
            client: client,
            realtimeClient: realtimeClient,
            viewerId: 1
        )

        client.blockResult = .success(())
        client.sendMessageResult = .success(
            MessageItem(
                id: "server-1",
                serverId: 1,
                roomId: 88,
                senderId: 1,
                content: "hello",
                createdAt: "2026-04-04T00:00:00Z",
                isPending: false
            )
        )

        await viewModel.blockCounterpart()
        viewModel.composerText = "hello"
        await viewModel.sendMessage()

        XCTAssertEqual(client.blockedMemberIds, [22])
        XCTAssertTrue(viewModel.isCounterpartBlockedByMe)
        XCTAssertTrue(client.sentPayloads.isEmpty)
    }

    func testLoadIfNeededRestoresBlockedStateFromBlockList() async {
        let client = MockMessagesClient()
        let realtimeClient = MockMessagesRealtimeClient()
        let viewModel = ChatRoomViewModel(
            context: MessageRoomContext(
                roomId: 88,
                postId: 2001,
                postTitle: "Study Post",
                roomTitle: "Study Post",
                otherMemberId: 22,
                counterpartDisplayName: "Anonymous 2",
                isAnonMe: false,
                isAnonOther: true,
                myLastReadMessageId: nil,
                otherLastReadMessageId: nil
            ),
            client: client,
            realtimeClient: realtimeClient,
            viewerId: 1
        )

        client.messagesResult = .success(
            MessagesPage(
                roomId: 88,
                messages: [],
                myLastReadMessageId: nil,
                otherLastReadMessageId: nil,
                nextBeforeMessageId: nil
            )
        )
        client.blockedMemberIdsResult = .success([22])

        await viewModel.loadIfNeeded()

        XCTAssertTrue(viewModel.isCounterpartBlockedByMe)
    }

    func testUnblockCounterpartReenablesSending() async {
        let client = MockMessagesClient()
        let realtimeClient = MockMessagesRealtimeClient()
        let viewModel = ChatRoomViewModel(
            context: MessageRoomContext(
                roomId: 88,
                postId: 2001,
                postTitle: "Study Post",
                roomTitle: "Study Post",
                otherMemberId: 22,
                counterpartDisplayName: "Anonymous 2",
                isAnonMe: false,
                isAnonOther: true,
                myLastReadMessageId: nil,
                otherLastReadMessageId: nil
            ),
            client: client,
            realtimeClient: realtimeClient,
            viewerId: 1
        )

        client.messagesResult = .success(
            MessagesPage(
                roomId: 88,
                messages: [],
                myLastReadMessageId: nil,
                otherLastReadMessageId: nil,
                nextBeforeMessageId: nil
            )
        )
        client.blockedMemberIdsResult = .success([22])
        client.sendMessageResult = .success(
            MessageItem(
                id: "server-2",
                serverId: 2,
                roomId: 88,
                senderId: 1,
                content: "after unblock",
                createdAt: "2026-04-04T00:00:00Z",
                isPending: false
            )
        )

        await viewModel.loadIfNeeded()
        await viewModel.unblockCounterpart()
        viewModel.composerText = "after unblock"
        await viewModel.sendMessage()

        XCTAssertEqual(client.unblockedMemberIds, [22])
        XCTAssertFalse(viewModel.isCounterpartBlockedByMe)
        XCTAssertEqual(client.sentPayloads.map(\.content), ["after unblock"])
    }
}
