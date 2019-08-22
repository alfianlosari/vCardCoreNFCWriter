//
//  NFCVCardReaderViewController.swift
//  VCardNFC
//
//  Created by Alfian Losari on 22/08/19.
//  Copyright © 2019 Alfian Losari. All rights reserved.
//

import UIKit
import CoreNFC

enum Item {
    case info
    case contact(label: String, value: String)
}

class NFCVCardReaderViewController: UITableViewController {
    
    var session: NFCNDEFReaderSession?
    
    var items: [Item] = [] {
        didSet {
            let previousRows = oldValue.enumerated().map { IndexPath(row: $0.offset, section: 0) }
            let newRows = items.enumerated().map { IndexPath(row: $0.offset, section: 0)}
            
            tableView.beginUpdates()
            tableView.deleteRows(at: previousRows, with: .automatic)
            tableView.insertRows(at: newRows, with: .automatic)
            tableView.endUpdates()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        items = [.info]
        tableView.tableFooterView = UIView()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tableView.register(RightDetailTableViewCell.self, forCellReuseIdentifier: "RightCell")
    }
    
    @IBAction func scanTapped(_ sender: Any) {
        guard NFCNDEFReaderSession.readingAvailable else {
            let alertController = UIAlertController(
                title: "Scanning Not Supported",
                message: "This device doesn't support tag scanning.",
                preferredStyle: .alert
            )
            alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alertController, animated: true, completion: nil)
            return
        }

        session = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        session?.alertMessage = "Hold your iPhone near the item to learn more about it."
        session?.begin()
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return items.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let item = items[indexPath.row]
        
        let cell: UITableViewCell
        switch item {
        case .info:
            cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
            cell.textLabel?.text = "Tap scan to begin Scanning your NFC tags containing vCard"
            
        case .contact(let label, let value):
            cell = tableView.dequeueReusableCell(withIdentifier: "RightCell", for: indexPath)
            cell.textLabel?.text = label
            cell.detailTextLabel?.text = value
        }
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.numberOfLines = 0
        return cell
        
    }
    
    
}

extension NFCVCardReaderViewController: NFCNDEFReaderSessionDelegate {
    
    private func proceedMessages(_ messages: [NFCNDEFMessage]) {
        guard let textPayload = messages.first?.records.first?.wellKnownTypeTextPayload().0,
            let contact = ContactForm(vCardText: textPayload)
            else {
                return
        }
        
        self.items = [
            .contact(label: "First Name", value: contact.firstName),
            .contact(label: "Last Name", value: contact.lastName),
            .contact(label: "Email", value: contact.email),
            .contact(label: "Address", value: contact.address)
            
        ]
    }
    
    /// - Tag: processingTagData
      func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
          DispatchQueue.main.async {
            self.proceedMessages(messages)
          }
      }
    
    

      /// - Tag: processingNDEFTag
      func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
          if tags.count > 1 {
              // Restart polling in 500ms
              let retryInterval = DispatchTimeInterval.milliseconds(500)
              session.alertMessage = "More than 1 tag is detected, please remove all tags and try again."
              DispatchQueue.global().asyncAfter(deadline: .now() + retryInterval, execute: {
                  session.restartPolling()
              })
              return
          }
          
          // Connect to the found tag and perform NDEF message reading
          let tag = tags.first!
          session.connect(to: tag, completionHandler: { (error: Error?) in
              if nil != error {
                  session.alertMessage = "Unable to connect to tag."
                  session.invalidate()
                  return
              }
              
              tag.queryNDEFStatus(completionHandler: { (ndefStatus: NFCNDEFStatus, capacity: Int, error: Error?) in
                  if .notSupported == ndefStatus {
                      session.alertMessage = "Tag is not NDEF compliant"
                      session.invalidate()
                      return
                  } else if nil != error {
                      session.alertMessage = "Unable to query NDEF status of tag"
                      session.invalidate()
                      return
                  }
                  
                  tag.readNDEF(completionHandler: { (message: NFCNDEFMessage?, error: Error?) in
                      var statusMessage: String
                      if nil != error || nil == message {
                          statusMessage = "Fail to read NDEF from tag"
                      } else {
                          statusMessage = "Found 1 NDEF message"
                        
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            if let message = message {
                                self.proceedMessages([message])
                            }

                        }
                       
                      }
                      session.alertMessage = statusMessage
                      session.invalidate()
                  })
              })
          })
      }
      
      /// - Tag: sessionBecomeActive
      func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
          
      }
      
      /// - Tag: endScanning
      func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
          // Check the invalidation reason from the returned error.
          if let readerError = error as? NFCReaderError {
              // Show an alert when the invalidation reason is not because of a
              // successful read during a single-tag read session, or because the
              // user canceled a multiple-tag read session from the UI or
              // programmatically using the invalidate method call.
              if (readerError.code != .readerSessionInvalidationErrorFirstNDEFTagRead)
                  && (readerError.code != .readerSessionInvalidationErrorUserCanceled) {
                  let alertController = UIAlertController(
                      title: "Session Invalidated",
                      message: error.localizedDescription,
                      preferredStyle: .alert
                  )
                  alertController.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                  DispatchQueue.main.async {
                      self.present(alertController, animated: true, completion: nil)
                  }
              }
          }

          // To read new tags, a new session instance is required.
          self.session = nil
      }

    
}


class RightDetailTableViewCell: UITableViewCell {
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: .value1, reuseIdentifier: reuseIdentifier)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
