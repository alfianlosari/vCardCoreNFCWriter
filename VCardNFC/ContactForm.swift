//
//  ContactForm.swift
//  VCardNFC
//
//  Created by Alfian Losari on 22/08/19.
//  Copyright © 2019 Alfian Losari. All rights reserved.
//

import Foundation
import Combine
import Contacts

class ContactForm: ObservableObject {
    
    @Published var firstName: String = ""
    @Published var lastName: String = ""
    @Published var email: String = ""
    @Published var address: String = ""
    
    init(){}
    init?(vCardText: String) {
        guard
            let data = vCardText.data(using: .utf8),
            let contact = try? CNContactVCardSerialization.contacts(with: data).first else {
                return nil
        }
        self.firstName = contact.givenName
        self.lastName = contact.familyName
        self.email = contact.emailAddresses.first?.value as String? ?? ""
        self.address = contact.postalAddresses.first?.value.street ?? ""
    }
    
    var toCNContact: CNContact {
        let contact = CNMutableContact()
        contact.givenName = firstName
        contact.familyName = lastName
        contact.emailAddresses.append(CNLabeledValue(label: "home", value: NSString(string: email)))
        let address = CNMutablePostalAddress()
        address.street = self.address
        contact.postalAddresses.append(CNLabeledValue(label: "home", value: address))
        return contact
    }
    
    var toVCardText: String? {
        guard let data = try?  CNContactVCardSerialization.data(with: [toCNContact]) else {
            return nil
        }
        let text = String(data: data, encoding: .utf8)!
        return text
    }
    
}

