//
//  DebugUtil.swift  v.0.2.0
//  SwiftUtilBiP
//
//  Created by Rudolf Farkas on 23.07.19.
//  Copyright © 2019 Rudolf Farkas. All rights reserved.
//

import Foundation

extension NSObject {
    /// Print current class and function names, optionally info
    ///
    /// - Note: Printing is enabled by DEBUG constant which is normally absent from release builds.
    ///
    /// - Requires: to be called from a subclass of NSObject
    ///
    /// - Parameters:
    ///  - info: information string
    ///   - fnc: current function (default value is the caller)
    func printClassAndFunc(info inf_: String = "", fnc fnc_: String = #function) {
        #if DEBUG
        print("---- \(String(describing: type(of: self))).\(fnc_)", inf_)
        #endif
    }
}
