//
//  MqttDecodeSubAck.swift
//  CocoaMQTT
//
//  Created by liwei wang on 2021/8/12.
//

import Foundation

public class MqttDecodeSubAck: NSObject {

    var totalCount = 0
    var dataIndex = 0
    var propertyLength: Int = 0

    public var reasonCodes: [CocoaMQTTSUBACKReasonCode] = []
    //public var reasonCode: CocoaMQTTSUBACKReasonCode?
    public var msgid: UInt16 = 0
    public var reasonString: String?
    public var userProperty: [String: String]?


    public func decodeSubAck(fixedHeader: UInt8, pubAckData: [UInt8]){
        totalCount = pubAckData.count
        dataIndex = 0
        //msgid
        guard let msgidResult = integerCompute(data: pubAckData, formatType: formatInt.formatUint16.rawValue, offset: dataIndex) else {
            return
        }
        
        msgid = UInt16(msgidResult.res)
        dataIndex = msgidResult.newOffset

        var protocolVersion = "";
        if let storage = CocoaMQTTStorage() {
            protocolVersion = storage.queryMQTTVersion()
        }

        if (protocolVersion == "5.0"){
            // 3.9.2.1  SUBACK Properties
            // 3.9.2.1.1  Property Length
            let propertyLengthVariableByteInteger = decodeVariableByteInteger(data: pubAckData, offset: dataIndex)
            propertyLength = propertyLengthVariableByteInteger.res
            dataIndex = propertyLengthVariableByteInteger.newOffset
            let occupyIndex = dataIndex

            while dataIndex < occupyIndex + propertyLength {
                let resVariableByteInteger = decodeVariableByteInteger(data: pubAckData, offset: dataIndex)
                dataIndex = resVariableByteInteger.newOffset
                let propertyNameByte = resVariableByteInteger.res
                guard let propertyName = CocoaMQTTPropertyName(rawValue: UInt8(propertyNameByte)) else {
                    break
                }


                switch propertyName.rawValue {
                // 3.9.2.1.2 Reason String
                case CocoaMQTTPropertyName.reasonString.rawValue:
                    guard let result = unsignedByteToString(data: pubAckData, offset: dataIndex) else {
                        break
                    }
                    reasonString = result.resStr
                    dataIndex = result.newOffset

                // 3.9.2.1.3 User Property
                case CocoaMQTTPropertyName.userProperty.rawValue:
                    var key:String?
                    var value:String?
                    guard let keyRes = unsignedByteToString(data: pubAckData, offset: dataIndex) else {
                        break
                    }
                    key = keyRes.resStr
                    dataIndex = keyRes.newOffset

                    guard let valRes = unsignedByteToString(data: pubAckData, offset: dataIndex) else {
                        break
                    }
                    value = valRes.resStr
                    dataIndex = valRes.newOffset

                    if let key {
                        if userProperty == nil {
                            userProperty = [:]
                        }
                        
                        userProperty?[key] = value
                    }
                default:
                    return
                }
            }
        }


        if dataIndex < totalCount {
            while dataIndex < totalCount {
                guard let reasonCode = CocoaMQTTSUBACKReasonCode(rawValue: pubAckData[dataIndex]) else {
                    return
                }
                reasonCodes.append(reasonCode)
                dataIndex += 1
            }
        }
        
    }

}


