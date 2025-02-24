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

#ifdef __IPHONE_9_0
#import <Contacts/Contacts.h>
#endif
#import "FastAddressBook.h"
#import "LinphoneManager.h"
#import "ContactsListView.h"
#import "Utils.h"
#import "linphoneapp-Swift.h"

@implementation FastAddressBook {
	CNContactStore* store;
}

+ (UIImage *)imageForContact:(Contact *)contact {
	@synchronized(LinphoneManager.instance.fastAddressBook.addressBookMap) {
		UIImage *retImage = nil;
		if (retImage == nil) {
			retImage = contact.friend && linphone_friend_get_addresses(contact.friend) ?
				[AvatarBridge imageForAddressWithAddress:linphone_friend_get_addresses(contact.friend)->data] :
			[AvatarBridge imageForInitialsWithContact:contact displayName:[contact displayName]];
		}
		if (retImage.size.width != retImage.size.height) {
			retImage = [retImage squareCrop];
		}
		return retImage;
	}
}

+ (UIImage *)imageForAddress:(const LinphoneAddress *)addr {
	if ([LinphoneManager isMyself:addr] && [LinphoneUtils hasSelfAvatar]) {
		return [LinphoneUtils selfAvatar];
	}
	return [AvatarBridge imageForAddressWithAddress:addr];
}

+ (UIImage *)imageForSecurityLevel:(LinphoneChatRoomSecurityLevel)level {
    switch (level) {
        case LinphoneChatRoomSecurityLevelUnsafe:
            return [UIImage imageNamed:@"security_alert_indicator.png"];
        case LinphoneChatRoomSecurityLevelEncrypted:
            return [UIImage imageNamed:@"security_1_indicator.png.png"];
        case LinphoneChatRoomSecurityLevelSafe:
            return [UIImage imageNamed:@"security_2_indicator.png.png"];
            
        default:
            return nil;
    }
}

+ (Contact *)getContact:(NSString *)address {
	if (LinphoneManager.instance.fastAddressBook != nil) {
		@synchronized(LinphoneManager.instance.fastAddressBook.addressBookMap) {
			return [LinphoneManager.instance.fastAddressBook.addressBookMap objectForKey:address];
		}
	}
  	return nil;
}

+ (Contact *)getContactWithAddress:(const LinphoneAddress *)address {
	Contact *contact = nil;
	if (address) {
		char *uri = linphone_address_as_string_uri_only(address);
		NSString *normalizedSipAddress = [FastAddressBook normalizeSipURI:[NSString stringWithUTF8String:uri] use_prefix:TRUE];
		contact = [FastAddressBook getContact:normalizedSipAddress];
		ms_free(uri);

		if (!contact) {
			LinphoneFriend *friend = linphone_core_find_friend(LC, address);
			bctbx_list_t *number_list = linphone_friend_get_phone_numbers(friend);
			bctbx_list_t *it;
			for (it = number_list ; it != NULL; it = it->next) {
				NSString *phone = [NSString stringWithUTF8String:it->data];
				LinphoneAccount *account = linphone_core_get_default_account(LC);
				
				if (account) {
					char *normvalue = linphone_account_normalize_phone_number(account, phone.UTF8String);
					LinphoneAddress *addr = linphone_account_normalize_sip_uri(account, normvalue);
					char *phone_addr = linphone_address_as_string_uri_only(addr);
					contact = [FastAddressBook getContact:[NSString stringWithUTF8String:phone_addr]];
					ms_free(phone_addr);
					linphone_address_unref(addr);
					bctbx_free(normvalue);
				} else {
					contact = [FastAddressBook getContact:phone];
				}
				
				if (contact) {
					break;
				}
			}
			bctbx_list_free(number_list);
		}
	}

	return contact;
}

+ (BOOL)isSipURI:(NSString *)address {
	return [address hasPrefix:@"sip:"] || [address hasPrefix:@"sips:"];
}

+ (BOOL)isSipAddress:(CNLabeledValue<CNInstantMessageAddress *> *)sipAddr {
	NSString *username = sipAddr.value.username;
	NSString *service = sipAddr.value.service;
	LOGI(@"Parsing contact with username : %@ and service : %@", username, service);
	if (!username || [username isEqualToString:@""])
		return FALSE;

	if (!service || [service isEqualToString:@""])
		return [FastAddressBook isSipURI:username];
	
	// use caseInsensitiveCompare, because ios13 saves "SIP" by "Sip"
	if ([service caseInsensitiveCompare:LinphoneManager.instance.contactSipField] == NSOrderedSame)
		return TRUE;

	return FALSE;
}

+ (NSString *)normalizeSipURI:(NSString *)address use_prefix:(BOOL)use_prefix {
	// replace all whitespaces (non-breakable, utf8 nbsp etc.) by the "classical" whitespace
	NSString *normalizedSipAddress = nil;
	LinphoneAddress *addr = linphone_core_interpret_url_2(LC, [address UTF8String], use_prefix);
	if (addr != NULL) {
		linphone_address_clean(addr);
		char *tmp = linphone_address_as_string(addr);
		normalizedSipAddress = [NSString stringWithUTF8String:tmp];
		ms_free(tmp);
		linphone_address_destroy(addr);
		return normalizedSipAddress;
	}else {
		normalizedSipAddress = [[address componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] componentsJoinedByString:@" "];
		return normalizedSipAddress;
	}
}

+ (BOOL)isAuthorized {
	return ![LinphoneManager.instance lpConfigBoolForKey:@"enable_native_address_book"] || [CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts] == CNAuthorizationStatusAuthorized;
}

- (FastAddressBook *)init {
	if ((self = [super init]) != nil) {
		store = [[CNContactStore alloc] init];
		_addressBookMap = [NSMutableDictionary dictionary];

		[NSNotificationCenter.defaultCenter addObserver:self
		selector:@selector(onPresenceChanged:)
			name:kLinphoneNotifyPresenceReceivedForUriOrTel
			object:nil];
	}
	self.needToUpdate = FALSE;
	if (floor(NSFoundationVersionNumber) >= NSFoundationVersionNumber_iOS_9_x_Max) {
		if ([CNContactStore class]) {
			// ios9 or later
			if (store == NULL)
				store = [[CNContactStore alloc] init];
			[self fetchContactsInBackGroundThread];
			[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateAddressBook:) name:CNContactStoreDidChangeNotification object:nil];
		}
	}
	return self;
}

- (void) loadLinphoneFriends {
	// load Linphone friends
	const MSList *lists = linphone_core_get_friends_lists(LC);
	while (lists) {
		LinphoneFriendList *fl = lists->data;
		const MSList *friends = linphone_friend_list_get_friends(fl);
		while (friends) {
			LinphoneFriend *f = friends->data;
			// only append friends that are not native contacts (already added
			// above)
			if (linphone_friend_get_ref_key(f) == NULL) {
				Contact *contact = [[Contact alloc] initWithFriend:f];
				contact.createdFromLdapOrProvisioning = true;
				[self registerAddrsFor:contact];
			}
			friends = friends->next;
		}
		linphone_friend_list_update_subscriptions(fl);
		lists = lists->next;
	}
	[self dumpContactsDisplayNamesToUserDefaults];
	
	[NSNotificationCenter.defaultCenter
		postNotificationName:kLinphoneAddressBookUpdate
		object:self];
}

- (void) fetchContactsInBackGroundThread{
	[_addressBookMap removeAllObjects];
	_addressBookMap = [NSMutableDictionary dictionary];
	
	if ([LinphoneManager.instance lpConfigBoolForKey:@"enable_native_address_book"]) {
		CNEntityType entityType = CNEntityTypeContacts;
		[store requestAccessForEntityType:entityType completionHandler:^(BOOL granted, NSError *_Nullable error) {
			BOOL success = FALSE;
			if(granted){
				LOGD(@"CNContactStore authorization granted");
				dispatch_async(dispatch_get_main_queue(), ^{
					if (bctbx_list_size(linphone_core_get_account_list(LC)) == 0 && ![LinphoneManager.instance lpConfigBoolForKey:@"use_rls_presence_requested"]) {
						//[SwiftUtil requestRLSPresenceAllowance];
					}
				});
				NSError *contactError;
				CNContactStore* store = [[CNContactStore alloc] init];
				[store containersMatchingPredicate:[CNContainer predicateForContainersWithIdentifiers:@[ store.defaultContainerIdentifier]] error:&contactError];
				NSArray *keysToFetch = @[
					CNContactEmailAddressesKey, CNContactPhoneNumbersKey,
					CNContactFamilyNameKey, CNContactGivenNameKey, CNContactNicknameKey,
					CNContactPostalAddressesKey, CNContactIdentifierKey,
					CNInstantMessageAddressUsernameKey, CNContactInstantMessageAddressesKey,
					CNInstantMessageAddressUsernameKey, CNContactImageDataKey, CNContactOrganizationNameKey
				];
				CNContactFetchRequest *request = [[CNContactFetchRequest alloc] initWithKeysToFetch:keysToFetch];
				
				success = [store enumerateContactsWithFetchRequest:request error:&contactError usingBlock:^(CNContact *__nonnull contact, BOOL *__nonnull stop) {
					if (contactError) {
						NSLog(@"error fetching contacts %@",
							  contactError);
					} else {
						Contact *newContact = [[Contact alloc] initWithCNContact:contact];
						[self registerAddrsFor:newContact];
					}
				}];
			}
			[self loadLinphoneFriends];
		}];
	} else {
		[self loadLinphoneFriends];
	}
	
	
}

-(void) updateAddressBook:(NSNotification*) notif {
	LOGD(@"address book has changed");
	self.needToUpdate = TRUE;
}

- (void)registerAddrsFor:(Contact *)contact {
	if (!contact)
		return;

	Contact* mContact = contact;
	if (!_addressBookMap)
		return;
	
	LinphoneAccount *account = linphone_core_get_default_account(LC);

	for (NSString *phone in mContact.phones) {
		char *normalizedPhone = account? linphone_account_normalize_phone_number(account, phone.UTF8String) : nil;
		NSString *name = [FastAddressBook normalizeSipURI:(normalizedPhone ? [NSString stringWithUTF8String:normalizedPhone] : phone) use_prefix:TRUE];
		if (phone != NULL)
			[_addressBookMap setObject:mContact forKey:(name ?: [FastAddressBook localizedLabel:phone])];

		if (normalizedPhone)
			ms_free(normalizedPhone);
	}

	for (NSString *sip in mContact.sipAddresses)
		[_addressBookMap setObject:mContact forKey:([FastAddressBook normalizeSipURI:sip use_prefix:TRUE] ?: sip)];
}

#pragma mark - Tools

+ (NSString *)localizedLabel:(NSString *)label {
	if (label)
		return [CNLabeledValue localizedStringForLabel:label];

	return @"";
}

+ (BOOL)contactHasValidSipDomain:(Contact *)contact {
	if (!contact)
		return NO;
	
	// Check if one of the contact' sip URI matches the expected SIP filter
	NSString *domain = LinphoneManager.instance.contactFilter;

	for (NSString *sip in contact.sipAddresses) {
		// check domain
		LinphoneAddress *address = linphone_core_interpret_url_2(LC, sip.UTF8String, true);
		if (address) {
			const char *dom = linphone_address_get_domain(address);
			BOOL match = false;
			if (dom != NULL) {
				NSString *contactDomain = [NSString stringWithCString:dom encoding:[NSString defaultCStringEncoding]];
				match = (([domain compare:@"*" options:NSCaseInsensitiveSearch] == NSOrderedSame) ||
						 ([domain compare:contactDomain options:NSCaseInsensitiveSearch] == NSOrderedSame));
			}
			linphone_address_destroy(address);
			if (match)
				return YES;
		}
	}
	return NO;
}

+ (BOOL) isSipURIValid:(NSString*)addr {
	NSString *domain = LinphoneManager.instance.contactFilter;
	LinphoneAddress* address = linphone_core_interpret_url_2(LC, addr.UTF8String, true);
	if (address) {
		const char *dom = linphone_address_get_domain(address);
		BOOL match = false;
		if (dom != NULL) {
			NSString *contactDomain = [NSString stringWithCString:dom encoding:[NSString defaultCStringEncoding]];
			match = (([domain compare:@"*" options:NSCaseInsensitiveSearch] == NSOrderedSame) ||
					 ([domain compare:contactDomain options:NSCaseInsensitiveSearch] == NSOrderedSame));
		}
		linphone_address_destroy(address);
		if (match) {
			return YES;
		}
	}
	return NO;
}

+ (NSString *)displayNameForContact:(Contact *)contact {
	return contact.displayName;
}
+ (NSString *)ogrganizationForContact:(Contact *)contact {
	return contact.organizationName;
}

+ (NSString *)displayNameForAddress:(const LinphoneAddress *)addr {
	Contact *contact = [FastAddressBook getContactWithAddress:addr];
	if (contact && ![contact.displayName isEqualToString:NSLocalizedString(@"Unknown", nil)])
		return [FastAddressBook displayNameForContact:contact];

	LinphoneFriend *friend = linphone_core_find_friend(LC, addr);
	if (friend)
		return [NSString stringWithUTF8String:linphone_friend_get_name(friend)];

	const char *displayName = linphone_address_get_display_name(addr);
	if (displayName)
		return [NSString stringWithUTF8String:displayName];

	const char *userName = linphone_address_get_username(addr);
	if (userName)
			return [NSString stringWithUTF8String:userName];

	return NSLocalizedString(@"Unknown", nil);
}


- (CNContact *)getCNContactFromContact:(Contact *)acontact {
  NSArray *keysToFetch = @[
    CNContactEmailAddressesKey, CNContactPhoneNumbersKey,
    CNContactFamilyNameKey, CNContactGivenNameKey, CNContactPostalAddressesKey,
    CNContactIdentifierKey, CNContactInstantMessageAddressesKey,
    CNInstantMessageAddressUsernameKey, CNContactImageDataKey, CNContactOrganizationNameKey
  ];
  CNMutableContact *mCNContact =
      [[store unifiedContactWithIdentifier:acontact.identifier
                               keysToFetch:keysToFetch
                                     error:nil] mutableCopy];
  return mCNContact;
}

- (BOOL)deleteCNContact:(CNContact *)contact {
		return TRUE;//[self deleteContact:] ;
}

- (BOOL)deleteContact:(Contact *)contact {
	[self removeContactFromUserDefaults:contact];

	CNSaveRequest *saveRequest = [[CNSaveRequest alloc] init];
	NSArray *keysToFetch = @[
							 CNContactEmailAddressesKey, CNContactPhoneNumbersKey,
							 CNContactInstantMessageAddressesKey, CNInstantMessageAddressUsernameKey,
							 CNContactFamilyNameKey, CNContactGivenNameKey, CNContactPostalAddressesKey,
							 CNContactIdentifierKey, CNContactImageDataKey, CNContactNicknameKey
							 ];
	CNMutableContact *mCNContact =
	[[store unifiedContactWithIdentifier:contact.identifier
							 keysToFetch:keysToFetch
								   error:nil] mutableCopy];
	if(mCNContact != nil){
		[saveRequest deleteContact:mCNContact];
		@try {
			[self removeFriend:contact ];
			[LinphoneManager.instance setContactsUpdated:TRUE];
			if([contact.sipAddresses count] > 0){
				for (NSString *sip in contact.sipAddresses) {
					[_addressBookMap removeObjectForKey:([FastAddressBook normalizeSipURI:sip use_prefix:TRUE] ?: sip)];
				}
			}
			if([contact.phones count] > 0){
				for (NSString *phone in contact.phones) {
					[_addressBookMap removeObjectForKey:([FastAddressBook normalizeSipURI:phone use_prefix:TRUE] ?: phone)];
				}
			}
			BOOL success = [store executeSaveRequest:saveRequest error:nil];
			NSLog(@"Success %d", success);
		} @catch (NSException *exception) {
			NSLog(@"description = %@", [exception description]);
			return FALSE;
		}
	}
	return TRUE;
}


- (BOOL)deleteAllContacts {
  NSArray *keys = @[ CNContactPhoneNumbersKey ];
  NSString *containerId = store.defaultContainerIdentifier;
  NSPredicate *predicate = [CNContact predicateForContactsInContainerWithIdentifier:containerId];
  NSError *error;
  NSArray *cnContacts = [store unifiedContactsMatchingPredicate:predicate
                                                    keysToFetch:keys
														  error:&error];
	if (error) {
		NSLog(@"error fetching contacts %@", error);
		return FALSE;
	} else {
		CNSaveRequest *saveRequest = [[CNSaveRequest alloc] init];
		for (CNContact *contact in cnContacts) {
		  [saveRequest deleteContact:[contact mutableCopy]];
		}
		@try {
			NSLog(@"Success %d", [store executeSaveRequest:saveRequest error:nil]);
		} @catch (NSException *exception) {
			NSLog(@"description = %@", [exception description]);
			return FALSE;
		}
	  NSLog(@"Deleted contacts %lu", (unsigned long)cnContacts.count);
	}
	return TRUE;
}

- (BOOL)saveContact:(Contact *)contact {
  return [self saveCNContact:contact.person contact:contact];
}

- (BOOL)saveCNContact:(CNContact *)cNContact contact:(Contact *)contact {
	CNSaveRequest *saveRequest = [[CNSaveRequest alloc] init];
	NSArray *keysToFetch = @[
		CNContactEmailAddressesKey, CNContactPhoneNumbersKey,
		CNContactInstantMessageAddressesKey, CNInstantMessageAddressUsernameKey,
		CNContactFamilyNameKey, CNContactGivenNameKey, CNContactPostalAddressesKey,
		CNContactIdentifierKey, CNContactImageDataKey, CNContactNicknameKey, CNContactOrganizationNameKey
	];
	CNMutableContact *mCNContact =
	[[store unifiedContactWithIdentifier:contact.identifier
							 keysToFetch:keysToFetch
								   error:nil] mutableCopy];
	if(mCNContact == NULL){
		[saveRequest addContact:[cNContact mutableCopy] toContainerWithIdentifier:nil];
	}else{
		[mCNContact setGivenName:contact.firstName];
		[mCNContact setFamilyName:contact.lastName];
		[mCNContact setNickname:contact.displayName];
		[mCNContact setOrganizationName:contact.organizationName];
		[mCNContact setPhoneNumbers:contact.person.phoneNumbers];
		[mCNContact setEmailAddresses:contact.person.emailAddresses];
		[mCNContact setInstantMessageAddresses:contact.person.instantMessageAddresses];
		[mCNContact setImageData:UIImageJPEGRepresentation(contact.avatar, 0.9f)];
		
		[saveRequest updateContact:mCNContact];
	}
	NSError *saveError;
	@try {
		[self updateFriend:contact];
		[LinphoneManager.instance setContactsUpdated:TRUE];
		NSLog(@"Success %d", [store executeSaveRequest:saveRequest error:&saveError]);
	} @catch (NSException *exception) {
		NSLog(@"=====>>>>> CNContact SaveRequest failed : description = %@", [exception description]);
		return FALSE;
	}
	[self fetchContactsInBackGroundThread];
	return TRUE;
}

-(void)updateFriend:(Contact*) contact{
	bctbx_list_t *phonesList = linphone_friend_get_phone_numbers(contact.friend);
	for (NSString *phone in contact.phones) {
		if(!(bctbx_list_find(phonesList, [phone UTF8String]))){
			linphone_friend_edit(contact.friend);
			linphone_friend_add_phone_number(contact.friend, [phone UTF8String]);
			linphone_friend_enable_subscribes(contact.friend, TRUE);
			linphone_friend_done(contact.friend);
		}
	}
	
	BOOL enabled = [LinphoneManager.instance lpConfigBoolForKey:@"use_rls_presence"];
	const MSList *lists = linphone_core_get_friends_lists(LC);
	while (lists) {
		linphone_friend_list_enable_subscriptions(lists->data, FALSE);
		linphone_friend_list_enable_subscriptions(lists->data, enabled);
		linphone_friend_list_update_subscriptions(lists->data);
		lists = lists->next;
	}
}

-(void)removeFriend:(Contact*) contact{
	BOOL enabled = [LinphoneManager.instance lpConfigBoolForKey:@"use_rls_presence"];
	const MSList *lists = linphone_core_get_friends_lists(LC);
	while (lists) {
		linphone_friend_list_remove_friend(lists->data, contact.friend);
		linphone_friend_list_enable_subscriptions(lists->data, FALSE);
		linphone_friend_list_enable_subscriptions(lists->data, enabled);
		linphone_friend_list_update_subscriptions(lists->data);
		lists = lists->next;
	}
}

- (void)reloadFriends {
	dispatch_async(dispatch_get_main_queue(), ^{
		[_addressBookMap enumerateKeysAndObjectsUsingBlock:^(NSString *name, Contact *contact, BOOL *stop) {
			[contact reloadFriend];
		}];
	});
}

- (void)clearFriends {
	[_addressBookMap enumerateKeysAndObjectsUsingBlock:^(NSString *name, Contact *contact, BOOL *stop) {
		[contact clearFriend];
	}];
}

- (void)dumpContactsDisplayNamesToUserDefaults {
	LOGD(@"dumpContactsDisplayNamesToUserDefaults");
	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kLinphoneMsgNotificationAppGroupId];
	__block NSDictionary *oldDisplayNames = [defaults dictionaryForKey:@"addressBook"];
	LinphoneAccount *account = linphone_core_get_default_account(LC);

	__block NSMutableDictionary *displayNames = [[NSMutableDictionary dictionary] init];
	[_addressBookMap enumerateKeysAndObjectsUsingBlock:^(NSString *name, Contact *contact, BOOL *stop) {
		if ([FastAddressBook isSipURIValid:name]) {
			NSString *key = name;
			LinphoneAddress *addr = linphone_address_new(name.UTF8String);

			if (addr && linphone_account_is_phone_number(account, linphone_address_get_username(addr))) {
				if (oldDisplayNames[name] != nil && [FastAddressBook isSipURI:oldDisplayNames[name]]) {
					NSString *addrForTel = [NSString stringWithString:oldDisplayNames[name]];
					/* we keep the link between tel number and sip addr to have the information quickly.
					 If we don't do that, between the startup and presence callback we don't have the dispay name for this address */
					LOGD(@"add %s -> %s link to userdefaults", name.UTF8String, addrForTel.UTF8String);
					[displayNames setObject:addrForTel forKey:name];
					key = addrForTel;
				}
			}
			LOGD(@"add %s to userdefaults", key.UTF8String);
			[displayNames setObject:[contact displayName] forKey:key];
			linphone_address_unref(addr);
		} else {
			LOGD(@"cannot add %s to userdefaults: bad sip address", name.UTF8String);
		}
	}];

	[defaults setObject:displayNames forKey:@"addressBook"];
}

- (void)removeContactFromUserDefaults:(Contact *)contact {
	LOGD(@"removeContactFromUserDefaults contact: [%p]", contact);
	NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kLinphoneMsgNotificationAppGroupId];
	NSMutableDictionary *displayNames = [[NSMutableDictionary alloc] initWithDictionary:[defaults dictionaryForKey:@"addressBook"]];
	if (displayNames == nil) return;

	
	LinphoneAccount *account = linphone_core_get_default_account(LC);
	for (NSString *phone in contact.phones) {
		char *normalizedPhone = account? linphone_account_normalize_phone_number(account, phone.UTF8String) : nil;
		NSString *name = [FastAddressBook normalizeSipURI:(normalizedPhone ? [NSString stringWithUTF8String:normalizedPhone] : phone) use_prefix:TRUE];
		if (phone != NULL) {
			if ([FastAddressBook isSipURI:displayNames[name]]) {
				LOGD(@"removed %s from userdefaults addressBook", ((NSString *)displayNames[name]).UTF8String);
				[displayNames removeObjectForKey:displayNames[name]];
			}
			[displayNames removeObjectForKey:name];
			LOGD(@"removed %s from userdefaults addressBook", ((NSString *)name).UTF8String);
		}

		if (normalizedPhone)
			ms_free(normalizedPhone);
	}

	NSMutableArray *addresses = contact.sipAddresses;
	for (id addr in addresses) {
		[displayNames removeObjectForKey:addr];
		LOGD(@"removed %s from userdefaults addressBook", ((NSString *)addr).UTF8String);
	}

	[defaults setObject:displayNames forKey:@"addressBook"];
}

- (void)onPresenceChanged:(NSNotification *)k {
	NSString *uri = [NSString stringWithUTF8String:[[k.userInfo valueForKey:@"uri"] pointerValue]];
	NSString *telAddr;

	if ([FastAddressBook isSipURI:uri]) {
		LinphoneAddress *addr = linphone_address_new(uri.UTF8String);
		if (linphone_account_is_phone_number(linphone_core_get_default_account(LC), linphone_address_get_username(addr))) {
			telAddr = uri;
		}
		linphone_address_unref(addr);
	} else {
		telAddr = [FastAddressBook normalizeSipURI:uri use_prefix:TRUE];
	}

	if (telAddr) {
		LOGD(@"presence changed for tel [%s]", telAddr.UTF8String);

		NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:kLinphoneMsgNotificationAppGroupId];
		NSMutableDictionary *displayNames = [[NSMutableDictionary alloc] initWithDictionary:[defaults dictionaryForKey:@"addressBook"]];
		if (displayNames == nil) return;

		id displayName = [displayNames objectForKey:telAddr];
		if (displayName == nil) return;

		const LinphonePresenceModel *m = [[k.userInfo valueForKey:@"presence_model"] pointerValue];
		char *str = linphone_presence_model_get_contact(m);
		if (str == nil) {
			return;
		}

		NSString *contact = [NSString stringWithUTF8String:str];
		ms_free(str);
		NSString *sipAddr = [FastAddressBook normalizeSipURI:contact use_prefix:TRUE];

		if (sipAddr != nil && [displayNames objectForKey:sipAddr] == nil) {
			[displayNames setObject:displayName forKey:sipAddr];
			[displayNames removeObjectForKey:telAddr];
			[displayNames setObject:sipAddr forKey:telAddr];
			LOGD(@"add %s -> %s link to userdefaults", telAddr.UTF8String, sipAddr.UTF8String);
			/* we keep the link between tel number and sip addr to have the information on the next startup.
			 If we don't do that, between the startup and this callback we don't have the dispay name for this address */
			LOGD(@"Replaced %s by %s in userdefaults addressBook", telAddr.UTF8String, sipAddr.UTF8String);
			[defaults setObject:displayNames forKey:@"addressBook"];
		}
	}
}

@end
