/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Alamofire
import Shared


public class RecordParseError : ErrorType {
    public var description: String {
        return "Failed to parse record."
    }
}

extension NSScanner {
    func scanLongLong() -> Int64? {
        var value: Int64 = 0
        if scanLongLong(&value) {
            return value
        }
        return nil
    }

    func scanDouble() -> Double? {
        var value: Double = 0
        if scanDouble(&value) {
            return value
        }
        return nil
    }
}

// Returns milliseconds. Handles decimals.
private func optionalSecondsHeader(input: AnyObject?) -> Int64? {
    if input == nil {
        return nil
    }

    if let val = input as? String {
        if let double = NSScanner(string: val).scanDouble() {
            return Int64(double * 1000)
        }
    }

    if let seconds: Double = input as? Double {
        // Oh for a BigDecimal library.
        return Int64(seconds * 1000)
    }

    if let seconds: NSNumber = input as? NSNumber {
        // Who knows.
        return seconds.longLongValue * 1000
    }

    return nil
}

private func optionalIntegerHeader(input: AnyObject?) -> Int64? {
    if input == nil {
        return nil
    }

    if let val = input as? String {
        return NSScanner(string: val).scanLongLong()
    }

    if let val: Double = input as? Double {
        // Oh for a BigDecimal library.
        return Int64(val)
    }

    if let val: NSNumber = input as? NSNumber {
        // Who knows.
        return val.longLongValue
    }

    return nil
}

public struct ResponseMetadata {
    public let alert: String?
    public let nextOffset: String?
    public let records: Int64?
    public let quotaRemaining: Int64?
    public let timestampMilliseconds: Int64        // Non-optional.
    public let lastModifiedMilliseconds: Int64?                // Included for all success responses.
    public let backoffMilliseconds: Int64?
    public let retryAfterMilliseconds: Int64?

    public init(headers: [NSObject : AnyObject]) {
        alert = headers["X-Weave-Alert"] as? String
        nextOffset = headers["X-Weave-Next-Offset"] as? String
        records = optionalIntegerHeader(headers["X-Weave-Records"])
        quotaRemaining = optionalIntegerHeader(headers["X-Weave-Quota-Remaining"])
        timestampMilliseconds = optionalSecondsHeader(headers["X-Weave-Timestamp"]) ?? -1
        lastModifiedMilliseconds = optionalSecondsHeader(headers["X-Last-Modified"])
        backoffMilliseconds = optionalSecondsHeader(headers["X-Weave-Backoff"]) ??
                              optionalSecondsHeader(headers["X-Backoff"])
        retryAfterMilliseconds = optionalSecondsHeader(headers["Retry-After"])
    }
}

public struct StorageResponse<T> {
    public let value: T
    public let metadata: ResponseMetadata
}

public typealias Authorizer = (NSMutableURLRequest) -> NSMutableURLRequest

// Don't forget to batch downloads.
public class Sync15StorageClient<T : CleartextPayloadJSON> {
    private let serverURI: NSURL
    private let authorizer: Authorizer
    private let factory: (String) -> T?
    private let workQueue: dispatch_queue_t
    private let resultQueue: dispatch_queue_t

    public init(serverURI: NSURL, authorizer: Authorizer, factory: (String) -> T?, workQueue: dispatch_queue_t, resultQueue: dispatch_queue_t) {
        self.serverURI = serverURI
        self.authorizer = authorizer
        self.factory = factory
        self.workQueue = workQueue
        self.resultQueue = resultQueue
    }

    private func requestGET(url: NSURL) -> Request {
        let req = NSMutableURLRequest(URL: url)
        req.HTTPMethod = Method.GET.rawValue
        req.addValue("application/json", forHTTPHeaderField: "Accept")
        let authorized: NSMutableURLRequest = self.authorizer(req)
        return Alamofire.request(authorized)
                        .validate(contentType: ["application/json"])
    }

    private func uriForRecord(guid: String) -> NSURL {
        return self.serverURI.URLByAppendingPathComponent(guid)
    }

    public func get(guid: String) -> Deferred<Result<StorageResponse<Record<T>>>> {
        let deferred = Deferred<Result<StorageResponse<Record<T>>>>(defaultQueue: self.resultQueue)

        let req = requestGET(uriForRecord(guid))
        req.responseJSON { (_, response, data, error) in
            if let error = error {
                deferred.fill(Result(failure: error))
                return
            }

            if response == nil {
                // TODO: better error.
                deferred.fill(Result(failure: RecordParseError()))
            }

            if let json: JSON = data as? JSON {
                let envelope = EnvelopeJSON(json)
                let record = Record<T>.fromEnvelope(envelope, payloadFactory: self.factory)
                if let record = record {
                    let metadata = ResponseMetadata(headers: response!.allHeaderFields)
                    let storageResponse = StorageResponse(value: record, metadata: metadata)
                    deferred.fill(Result(success: storageResponse))
                    return
                }
            }

            deferred.fill(Result(failure: RecordParseError()))
            return
        }

        return deferred
    }

    /**
     * Unlike every other Sync client, we use the application/json format for fetching
     * multiple requests. The others use application/newlines. We don't want to write
     * another Serializer, and we're loading everything into memory anyway.
     */
    public func getSince(since: Int64) -> Deferred<Result<StorageResponse<[Record<T>]>>> {
        let deferred = Deferred<Result<StorageResponse<[Record<T>]>>>(defaultQueue: self.resultQueue)

        let req = requestGET(self.serverURI)
        req.responseParsedJSON { (_, response, data, error) in
            if let error = error {
                deferred.fill(Result(failure: error))
                return
            }

            if response == nil {
                // TODO: better error.
                deferred.fill(Result(failure: RecordParseError()))
            }

            if let json: JSON = data as? JSON {
                func recordify(json: JSON) -> Record<T>? {
                    let envelope = EnvelopeJSON(json)
                    return Record<T>.fromEnvelope(envelope, payloadFactory: self.factory)
                }
                if let arr = json.asArray? {
                    let metadata = ResponseMetadata(headers: response!.allHeaderFields)
                    let response = StorageResponse(value: optFilter(arr.map(recordify)), metadata: metadata)
                    deferred.fill(Result(success: response))
                    return
                }
            }

            deferred.fill(Result(failure: RecordParseError()))
            return
        }

        return deferred
    }
}

extension Request {
    public func responseParsedJSON(completionHandler: (NSURLRequest, NSHTTPURLResponse?, AnyObject?, NSError?) -> Void) -> Self {
        return response(serializer: Request.ParsedJSONResponseSerializer(), completionHandler: { (request, response, JSON, error) in
            completionHandler(request, response, JSON, error)
        })
    }

    public class func ParsedJSONResponseSerializer() -> Serializer {
        return { (request, response, data) in
            if data == nil || data?.length == 0 {
                return (nil, nil)
            }

            let json = JSON(data: data!)
            if json.isError {
                return (nil, json.asError)
            }
            return (json, nil)
        }
    }
}
