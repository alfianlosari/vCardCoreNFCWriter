//
//  NFCReaderTableViewController.swift
//  VCardNFC
//
//  Created by Alfian Losari on 22/08/19.
//  Copyright © 2019 Alfian Losari. All rights reserved.
//

import UIKit
import Combine
import Contacts
import CoreNFC

class NFCVCardWriterViewController: UITableViewController {
    
    @IBOutlet weak var firstNameTextField: UITextField!
    @IBOutlet weak var lastNameTextField: UITextField!
    @IBOutlet weak var emailTextField: UITextField!
    @IBOutlet weak var addressTextView: UITextView!
    
    var readerSession: NFCNDEFReaderSession?
    var ndefMessage: NFCNDEFMessage?
    
    var contactForm = ContactForm()
    
    private func configureObservers() {
        _ = Publishers.CombineLatest4(contactForm.$firstName, contactForm.$lastName, contactForm.$email, contactForm.$address)
            .receive(on: RunLoop.main)
            .sink {[unowned self] (firstName, lastName, email, address) in
                let isEnabled: Bool
                if !firstName.isEmpty && !lastName.isEmpty && !email.isEmpty {
                    isEnabled = true
                } else {
                    isEnabled = false
                }
                self.configureNavItem(isEnabled)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        configureObservers()
        let tapGR = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard(_:)))
        view.addGestureRecognizer(tapGR)
    }
    
    @objc func writeToNFC(_ sender: Any) {
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
        
        readerSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        readerSession?.alertMessage = "Hold your iPhone near a writable NFC tag to create vCard."
        readerSession?.begin()
    }
    
    private func configureNavItem(_ isEnabled: Bool) {
        if isEnabled {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "Write",
                                                                style: .plain, target: self,
                                                                action: #selector(writeToNFC(_:)))
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }
    
    @objc func dismissKeyboard(_ sender: Any) {
        view.endEditing(true)
    }
    
}

extension NFCVCardWriterViewController: NFCNDEFReaderSessionDelegate {
    
    // MARK: - Private functions
    func createVCardPayload() -> NFCNDEFPayload? {
        guard let contactText = self.contactForm.toVCardText else {
            return nil
        }
        let textPayload = NFCNDEFPayload.wellKnownTypeTextPayload(string: contactText, locale: Locale(identifier: "En"))
        return textPayload
    }
    
    func tagRemovalDetect(_ tag: NFCNDEFTag) {
        // In the tag removal procedure, you connect to the tag and query for
        // its availability. You restart RF polling when the tag becomes
        // unavailable; otherwise, wait for certain period of time and repeat
        // availability checking.
        self.readerSession?.connect(to: tag) { (error: Error?) in
            if error != nil || !tag.isAvailable {
                
                
                self.readerSession?.restartPolling()
                return
            }
            DispatchQueue.global().asyncAfter(deadline: DispatchTime.now() + .milliseconds(500), execute: {
                self.tagRemovalDetect(tag)
            })
        }
    }
    
    // MARK: - NFCNDEFReaderSessionDelegate
    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        if let textPayload = self.createVCardPayload() {
            ndefMessage = NFCNDEFMessage(records: [textPayload])
        }
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // If necessary, you may handle the error. Note session is no longer valid.
        // You must create a new session to restart RF polling.
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Do not add code in this function. This method isn't called
        // when you provide `reader(_:didDetect:)`.
    }
    
    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        if tags.count > 1 {
            session.alertMessage = "More than 1 tags found. Please present only 1 tag."
            self.tagRemovalDetect(tags.first!)
            return
        }
        
        // You connect to the desired tag.
        let tag = tags.first!
        session.connect(to: tag) { (error: Error?) in
            if error != nil {
                session.restartPolling()
                return
            }
            
            // You then query the NDEF status of tag.
            tag.queryNDEFStatus() { (status: NFCNDEFStatus, capacity: Int, error: Error?) in
                if error != nil {
                    session.invalidate(errorMessage: "Fail to determine NDEF status.  Please try again.")
                    return
                }
                
                if status == .readOnly {
                    session.invalidate(errorMessage: "Tag is not writable.")
                } else if status == .readWrite {
                    if self.ndefMessage!.length > capacity {
                        session.invalidate(errorMessage: "Tag capacity is too small.  Minimum size requirement is \(self.ndefMessage!.length) bytes.")
                        return
                    }
                    
                    // When a tag is read-writable and has sufficient capacity,
                    // write an NDEF message to it.
                    tag.writeNDEF(self.ndefMessage!) { (error: Error?) in
                        if error != nil {
                            session.invalidate(errorMessage: "Update tag failed. Please try again.")
                        } else {
                            session.alertMessage = "vCard Created!"
                            session.invalidate()
                        }
                    }
                } else {
                    session.invalidate(errorMessage: "Tag is not NDEF formatted.")
                }
            }
        }
    }
}



extension NFCVCardWriterViewController: UITextFieldDelegate {
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if let text = textField.text,
            let textRange = Range(range, in: text) {
            let updatedText = text.replacingCharacters(in: textRange,
                                                       with: string)
            if textField === firstNameTextField {
                contactForm.firstName = updatedText
            } else if textField === lastNameTextField {
                contactForm.lastName = updatedText
            } else {
                contactForm.email = updatedText
            }
        }
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        view.endEditing(true)
        return true
    }
    
}

extension NFCVCardWriterViewController: UITextViewDelegate {
    
    func textViewDidChange(_ textView: UITextView) {
        contactForm.address = textView.text
    }
}
