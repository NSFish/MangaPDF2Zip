//
//  main.swift
//  PDF2Zip
//
//  Created by nsfish on 2021/6/19.
//

import Foundation

/*
 1. 获取 url
 2. 提取输入的参数中的所有文件
 3. 逐个处理
    3.1 解压缩(unar)
    3.2 cd 进入，按顺序重命名文件
    3.3 后退，压缩
    3.4 删除文件夹和 PDF
 */

var urlString = ""
for (index, _) in CommandLine.arguments.enumerated() {
    if (index == 1) {
        urlString = CommandLine.arguments[index]
    }
}

let fileManager = FileManager.default

let url = URL(fileURLWithPath: urlString)

var files = [URL]()
if !url.hasDirectoryPath {
    files.append(url)
}
else {
    if let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
        for case let fileURL as URL in enumerator {
            do {
                let fileAttributes = try fileURL.resourceValues(forKeys:[.isRegularFileKey])
                if fileAttributes.isRegularFile!
                    && fileURL.pathExtension.lowercased() == "pdf" {
                    files.append(fileURL)
                }
            } catch { print(error, fileURL) }
        }
    }
}

files.forEach { pdf2Zip(with: $0) }

//MARK:- 流程
func pdf2Zip(with fileURL: URL) {
    let fileNameDirectory = fileURL.deletingPathExtension()
    if fileManager.fileExists(atPath: fileNameDirectory.path) {
        try! fileManager.removeItem(at: fileNameDirectory)
    }
    
    decompress(fileURL: fileURL)
    renameImagesBySerialNumber(in: fileURL.deletingPathExtension())
    var zipURL = zip(directory: fileNameDirectory)
    
    // 复制 PDF 的标签到 zip 上
    let tags = try! fileURL.resourceValues(forKeys: [URLResourceKey.tagNamesKey])
    try! zipURL.setResourceValues(tags)
    
    try! fileManager.removeItem(at: fileNameDirectory)
    try! fileManager.removeItem(at: fileURL)
}

func decompress(fileURL: URL) {
    let directoryURL = fileURL.deletingLastPathComponent()
    
    let task = Process()
    task.currentDirectoryURL = directoryURL
    task.executableURL = URL.init(fileURLWithPath: "/Users/nsfish/Documents/Github/PersonalScripts/unar")
    // unar
    // -force-directory (-d)                   Always create a containing directory for the contents of the unpacked archive. By default, a directory is created if there is more than one top-level file or folder.
    // 兼容只有一张图的 PDF，即使解压出来的内容只有一个文件，也创建文件夹
    task.arguments = [fileURL.path, "-d"]
    
    let outputPipe = Pipe()
    task.standardOutput = outputPipe
    
    task.launch()
    
    task.waitUntilExit()
}

func renameImagesBySerialNumber(in directoryURL: URL) {
    // 不知为何 rename 在这里用不了，报错是 unparseable counter format
    // 只好自己来了
    // rename -N ...01 -X -e '$_ = "$N"' *
    //    let task = Process()
    //    task.currentDirectoryURL = directoryURL
    //    task.executableURL = URL.init(fileURLWithPath: "/usr/local/bin/rename")
    //    task.arguments = ["-c", "-N ...01 -X -e '$_ = \"$N\"' *"]
    //
    //    let pipeStandard = Pipe()
    //    task.standardOutput = pipeStandard
    //
    //    task.launch()
    //    task.waitUntilExit()
    do {
        let files = try fileManager.contentsOfDirectory(at: directoryURL,
                                                        includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
            .sorted { compareFileName(left: $0.lastPathComponent, right: $1.lastPathComponent) }
        
        for (index, fileURL) in files.enumerated() {
            let newNameURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent(serialNumberFrom(index: index + 1, totalCount: files.count))
                .appendingPathExtension(fileURL.pathExtension)
            try fileManager.moveItem(at: fileURL, to: newNameURL)
        }
    } catch {
        
    }
}

// 直接用 QuickLook 看到的文件顺序是乱的，但是用漫画软件打开是正确的
func zip(directory: URL) -> URL {
    let archiveURL = directory.appendingPathExtension("zip")
    if fileManager.fileExists(atPath: archiveURL.path) {
        try! fileManager.removeItem(at: archiveURL)
    }
    // if we encounter an error, store it here
    var error: NSError?
    
    let coordinator = NSFileCoordinator()
    // zip up the documents directory
    // this method is synchronous and the block will be executed before it returns
    // if the method fails, the block will not be executed though
    // if you expect the archiving process to take long, execute it on another queue
    coordinator.coordinate(readingItemAt: directory, options: [.forUploading], error: &error) { zipUrl in
        // zipUrl points to the zip file created by the coordinator
        // zipUrl is valid only until the end of this block, so we move the file to a temporary folder
        try! fileManager.moveItem(at: zipUrl, to: archiveURL)
    }
    
    return archiveURL
}

//MARK:- Helper
func compareFileName(left: String, right: String) -> Bool {
    // 如果解压出来的文件中无法读取到数字，则保持原顺序不变
    if !left.contains("Page")
        || !right.contains("Page") {
        return true
    }
    
    let leftFirst = left.components(separatedBy: ",").first!
    let leftPage = leftFirst.components(separatedBy: " ").last!
    
    let rightFirst = right.components(separatedBy: ",").first!
    let rightPage = rightFirst.components(separatedBy: " ").last!
    
    return Int(leftPage)! < Int(rightPage)!
}

func serialNumberFrom(index: Int, totalCount: Int) -> String {
    var result = ""
    
    var serialNumberLength = 1
    if totalCount >= 10 && totalCount <= 99 {
        serialNumberLength = 2
    }
    else if totalCount > 99 {
        serialNumberLength = 3
    }
    
    let indexString = String(index)
    let difference = serialNumberLength - indexString.count
    if difference > 0 {
        for _ in 0..<difference {
            result.append("0")
        }
    }
    result.append(indexString)
    
    return result
}


