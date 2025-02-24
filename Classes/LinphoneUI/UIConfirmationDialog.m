/*
 * Copyright (c) 2010-2020 Belledonne Communications SARL.
 *
 * This file is part of linphone-iphone
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

#import "UIConfirmationDialog.h"
#import "PhoneMainView.h"
#import "linphoneapp-Swift.h"

@implementation UIConfirmationDialog
+ (UIConfirmationDialog *)initDialog:(NSString *)cancel
                           confirmMessage:(NSString *)confirm
                            onCancelClick:(UIConfirmationBlock)onCancel
                      onConfirmationClick:(UIConfirmationBlock)onConfirm
                             inController:(UIViewController *)controller {
    UIConfirmationDialog *dialog =
    [[UIConfirmationDialog alloc] initWithNibName:NSStringFromClass(self.class) bundle:NSBundle.mainBundle];
    
    dialog.view.frame = PhoneMainView.instance.mainViewController.view.frame;
    [controller.view addSubview:dialog.view];
    [controller addChildViewController:dialog];
    dialog.backgroundColor.layer.cornerRadius = 10;
    dialog.backgroundColor.layer.masksToBounds = true;
    
    dialog->onCancelCb = onCancel;
    dialog->onConfirmCb = onConfirm;
    
    if (cancel) {
        [dialog.cancelButton setTitle:cancel forState:UIControlStateNormal];
    }
    if (confirm) {
        [dialog.confirmationButton setTitle:confirm forState:UIControlStateNormal];
    }
    
    dialog.confirmationButton.layer.borderColor =
    [[UIColor colorWithPatternImage:[UIImage imageNamed:@"color_A.png"]] CGColor];
    dialog.cancelButton.layer.borderColor =
    [[UIColor colorWithPatternImage:[UIImage imageNamed:@"color_F.png"]] CGColor];
	if (linphone_core_get_post_quantum_available()) {
		[dialog.securityImage setImage:[UIImage imageNamed:@"post_quantum_secure.png"]];
	}
    return dialog;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self
                                                                                        action:@selector(onCancelClick:)];
    tapGestureRecognizer.delegate = self;
    [self.firstView addGestureRecognizer:tapGestureRecognizer];
}


+ (UIConfirmationDialog *)ShowWithMessage:(NSString *)message
							cancelMessage:(NSString *)cancel
						   confirmMessage:(NSString *)confirm
							onCancelClick:(UIConfirmationBlock)onCancel
					  onConfirmationClick:(UIConfirmationBlock)onConfirm
							 inController:(UIViewController *)controller {
	UIConfirmationDialog *dialog =
    [UIConfirmationDialog initDialog:cancel confirmMessage:confirm onCancelClick:onCancel onConfirmationClick:onConfirm inController:controller];
    [dialog.titleLabel setText:message];
	return dialog;
}

+ (UIConfirmationDialog *)ShowWithMessage:(NSString *)message
							cancelMessage:(NSString *)cancel
						   confirmMessage:(NSString *)confirm
							onCancelClick:(UIConfirmationBlock)onCancel
					  onConfirmationClick:(UIConfirmationBlock)onConfirm {
	return [self ShowWithMessage:message
				   cancelMessage:cancel
				  confirmMessage:confirm
				   onCancelClick:onCancel
			 onConfirmationClick:onConfirm
					inController:PhoneMainView.instance.mainViewController];
}

+ (UIConfirmationDialog *)ShowWithAttributedMessage:(NSMutableAttributedString *)attributedText
                            cancelMessage:(NSString *)cancel
                           confirmMessage:(NSString *)confirm
                            onCancelClick:(UIConfirmationBlock)onCancel
                      onConfirmationClick:(UIConfirmationBlock)onConfirm {
    UIConfirmationDialog *dialog =
    [UIConfirmationDialog initDialog:cancel confirmMessage:confirm onCancelClick:onCancel onConfirmationClick:onConfirm inController:PhoneMainView.instance.mainViewController];
    dialog.titleLabel.attributedText = attributedText;
    return dialog;
}

- (void)setSpecialColor {
	[_confirmationButton setBackgroundImage:[UIImage imageNamed:@"color_L.png"] forState:UIControlStateNormal];
	[_cancelButton setBackgroundImage:[UIImage imageNamed:@"color_I.png"] forState:UIControlStateNormal];
	[_cancelButton setTitleColor:[UIColor colorWithPatternImage:[UIImage imageNamed:@"color_H.png"]] forState:UIControlStateNormal];
	
	_confirmationButton.layer.borderColor =
	[[UIColor colorWithPatternImage:[UIImage imageNamed:@"color_L.png"]] CGColor];
	_cancelButton.layer.borderColor =
	[[UIColor colorWithPatternImage:[UIImage imageNamed:@"color_A.png"]] CGColor];
}

-(void) setWhiteCancel {
	[_cancelButton setBackgroundImage:nil forState:UIControlStateNormal];
	[_cancelButton setBackgroundColor:UIColor.whiteColor];
	[_cancelButton setTitleColor:VoipTheme.voip_dark_gray forState:UIControlStateNormal];
	_cancelButton.layer.borderColor = UIColor.whiteColor.CGColor;
}

- (IBAction)onCancelClick:(id)sender {
	[self.view removeFromSuperview];
	[self removeFromParentViewController];
	if (onCancelCb) {
		onCancelCb();
	}
}

- (IBAction)onConfirmationClick:(id)sender {
	[self.view removeFromSuperview];
	[self removeFromParentViewController];
	if (onConfirmCb) {
		onConfirmCb();
	}
}

- (IBAction)onAuthClick:(id)sender {
    BOOL notAskAgain = ![LinphoneManager.instance lpConfigBoolForKey:@"confirmation_dialog_before_sas_call_not_ask_again"];
    UIImage *image = notAskAgain ? [UIImage imageNamed:@"checkbox_checked.png"] : [UIImage imageNamed:@"checkbox_unchecked.png"];
    [_authButton setImage:image forState:UIControlStateNormal];
    [LinphoneManager.instance lpConfigSetBool:notAskAgain forKey:@"confirmation_dialog_before_sas_call_not_ask_again"];
}

- (void)dismiss {
	[self onCancelClick:nil];
}

- (IBAction)onSubscribeTap:(id)sender {
	UIGestureRecognizer *gest = sender;
	NSString *url = ((UILabel *)gest.view).text;
	[SwiftUtil openUrlWithUrlString:url];
}
@end
