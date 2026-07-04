import Foundation
import Testing
@testable import StrictID

// Golden vectors shared with the Go strictid library's golden_test.go. They pin down the
// canonical encoding (alphabet, minimum length, sqids algorithm) across both implementations, so
// cross-language compatibility can't drift unnoticed.

@Suite("Golden")
struct GoldenTests {

    @Test("String values match the golden vectors from the Go strictid library")
    func goldenIDsMatchGo() throws {
        struct Vec {
            let shard: Int64
            let id: Int64
            let kind: String
            let str: String
            let raw: [Int64]
        }
        let vecs: [Vec] = [
            Vec(shard: 0, id: 0, kind: "T", str: "T__wsVco91", raw: [0, 84, 0]),
            Vec(shard: 0, id: 1, kind: "P", str: "P__mfWECMA", raw: [0, 80, 1]),
            Vec(shard: 0, id: 9007199254740991, kind: "T", str: "T__3TE4dHokVx6vKvb", raw: [0, 84, 9007199254740991]),
            Vec(shard: 1000000, id: 999999, kind: "P", str: "P__CfTFObGXeZxrN", raw: [1000000, 80, 999999]),
            Vec(shard: 1234567890123, id: 9007199254000000, kind: "T", str: "T__M2p1Twud4ecYeDQ45tsLf", raw: [1234567890123, 84, 9007199254000000]),
            Vec(shard: 1234567890, id: 9876543210, kind: "PL", str: "PL_lDm0uwOeWd1aU9uIj", raw: [1234567890, 156, 9876543210]),
            Vec(shard: 1337, id: 42, kind: "P", str: "P__zuYa75Z5", raw: [1337, 80, 42]),
            Vec(shard: 1337, id: 99999, kind: "H", str: "H__rTBmQRi9v2", raw: [1337, 72, 99999]),
            Vec(shard: 42, id: 1000, kind: "H", str: "H__kCzaLTO5", raw: [42, 72, 1000]),
            Vec(shard: 999, id: 12345, kind: "PL", str: "PL_0mqtJaT7NR", raw: [999, 156, 12345]),
        ]

        for v in vecs {
            let got = try ID(shardNumber: v.shard, identifier: v.id, entityKind: v.kind)
            #expect(got.stringValue == v.str, "New(\(v.shard),\(v.id),\(v.kind)).stringValue")
            #expect(got.rawValues == v.raw, "New(\(v.shard),\(v.id),\(v.kind)).rawValues")

            let parsed = try ID.parse(input: v.str)
            #expect(parsed == got)
        }
    }

    @Test("External UUIDs match the golden vectors from the Go strictid library")
    func goldenExternalUUIDMatchesGo() throws {
        struct Vec {
            let uuidStr: String
            let str: String
            let raw: [Int64]
        }
        let vecs: [Vec] = [
            Vec(uuidStr: "00000000-0000-0000-0000-000000000000", str: "_U_brd1jN", raw: [0, 0, 0]),
            Vec(uuidStr: "017f22e2-79b0-7cc3-a8c4-dc0c0c07398f", str: "_U_yE7ZdlvmErxz0ODyLoChboOa", raw: [6495697866464582, 24520, 1367844206360975]),
            Vec(uuidStr: "f47ac10b-58cc-4372-b567-0e02b2c3d479", str: "_U_fa33IoDBnFpwLjvPyqgSHXkrU", raw: [2351607909684651, 4005552, 1985729588876409]),
            Vec(uuidStr: "ffffffff-ffff-ffff-ffff-ffffffffffff", str: "_U_p1p4dV0i05G18w7WxpsHE3G3w", raw: [9007199254740991, 4194303, 9007199254740991]),
        ]

        for v in vecs {
            let uuid = UUID(uuidString: v.uuidStr)!
            let packed = ID.pack(uuid)
            #expect(packed == v.raw, "pack(\(v.uuidStr))")

            let id = try ID(externalUUID: uuid)
            #expect(id.stringValue == v.str, "NewExternalUUID(\(v.uuidStr)).stringValue")

            let back = id.externalUUID
            #expect(back == uuid)
        }
    }
}
