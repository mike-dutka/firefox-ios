//
//  BlockView.swift
//  Client
//
//  Created by Mykhailo Dutka on 7/6/16.
//  Copyright © 2016 Mozilla. All rights reserved.
//

import UIKit

let kPasswdKey = "kPasswdKey"

class BlockView: UIView {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        self.setup()
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        self.setup()
    }
    
    private func setup(){
        self.backgroundColor = .white
        
        let img = UIImageView(frame: CGRect(x:0, y:0, width:130, height:130))
        img.frame.center = CGPoint(x: self.bounds.size.width/2.0, y: self.bounds.size.height/2.0)
        img.autoresizingMask = [.flexibleTopMargin, .flexibleBottomMargin, .flexibleLeftMargin, .flexibleRightMargin]
        img.backgroundColor = self.backgroundColor
        img.contentMode = .scaleToFill
        img.image = UIImage(named: "splash")
        self.addSubview(img)
        
        let lbl = UILabel(frame: CGRect(x: 5, y:5, width:20, height:20))
        lbl.backgroundColor = self.backgroundColor
        lbl.textColor = .lightGray
        lbl.text = "+"
        self.addSubview(lbl)
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleAction))
        tapRecognizer.numberOfTapsRequired = 3
        
        let tapUpdateRecognizer = UITapGestureRecognizer(target: self, action: #selector(handleSetPassword))
        tapUpdateRecognizer.numberOfTapsRequired = 4
        
        tapRecognizer.require(toFail: tapUpdateRecognizer)
        
        self.addGestureRecognizer(tapRecognizer)
        self.addGestureRecognizer(tapUpdateRecognizer)
    }
    
    @objc func handleAction() {
        guard let pwd = UserDefaults.standard.string(forKey: kPasswdKey), (pwd.isEmpty == false) else {
            handleSetPassword()
            return
        }
        
        let alert = UIAlertController(title: "", message: "", preferredStyle: .alert)
        alert.addTextField { textField in
            textField.textAlignment = .center
            textField.keyboardType = .phonePad
            textField.isSecureTextEntry = true
        }
        
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { action in
            if let tf = alert.textFields?.first, (tf.text == pwd) {
                self.unhide()
            }
        }))
        
        // Get the active window scene
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            // Get the root view controller from the first window
            if let rootViewController = windowScene.windows.first?.rootViewController {
                // Present the alert
                rootViewController.present(alert, animated: true, completion: nil)
            }
        }

    }
    
    @objc func handleSetPassword(){
        let alert = UIAlertController(title: "Set PIN", message: "", preferredStyle: .alert)
        
        var oldPasswd: String?
        
        if let pwd = UserDefaults.standard.string(forKey: kPasswdKey), (pwd.isEmpty == false) {
            alert.addTextField { textField in
                textField.textAlignment = .center
                textField.keyboardType = .phonePad
                textField.isSecureTextEntry = true
                textField.placeholder = "old PIN"
            }
            
            oldPasswd = pwd
        }
        
        alert.addTextField { textField in
            textField.textAlignment = .center
            textField.keyboardType = .phonePad
            textField.isSecureTextEntry = true
            textField.placeholder = "PIN"
        }
        
        alert.addAction(UIAlertAction(title: "OK", style: .default, handler: { action in
            
            let pinOld = (alert.textFields?.count == 2 ? alert.textFields?.first : nil)?.text
            let pinNew = (alert.textFields?.count == 2 ? alert.textFields?.last : alert.textFields?.first)?.text
            
            guard (pinOld == nil) || (pinOld! == oldPasswd) else {
                return
            }
            
            guard pinNew?.isEmpty == false else {
                return
            }
            
            UserDefaults.standard.setValue(pinNew!, forKey: kPasswdKey)
            UserDefaults.standard.synchronize()
            
            self.unhide()
        }))
        
        // Get the active window scene
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            // Get the root view controller from the first window
            if let rootViewController = windowScene.windows.first?.rootViewController {
                // Present the alert
                rootViewController.present(alert, animated: true, completion: nil)
            }
        }
    }
    
    func unhide() {
        self.removeFromSuperview()
    }
}
