// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include "AuthStore.h"
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
static const char* Inbox="/var/mobile/Documents/phoenix-auth-inbox/credentials.json";
static NSDictionary* query(void) {
 return @{(__bridge id)kSecAttrAccessGroup:@"PHOENIXDEV.org.ipad2mediaplayer.receiver",
  (__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
  (__bridge id)kSecAttrService:@"org.ipad2mediaplayer.cspot.credentials",
  (__bridge id)kSecAttrAccount:@"primary"};
}
static BOOL valid(NSData* data) {
 if(!data.length || data.length>4095)return NO;
 id value=[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
 if(![value isKindOfClass:NSDictionary.class])return NO;
 NSString* user=value[@"username"];NSString* encoded=value[@"authData"];id type=value[@"authType"];
 if(![user isKindOfClass:NSString.class] || ![encoded isKindOfClass:NSString.class] || ![type isKindOfClass:NSNumber.class])return NO;
 if(!user.length || [user lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>29)return NO;
 if(![type isEqual:@1] && ![type isEqual:@2])return NO;
 NSData* bytes=[[NSData alloc] initWithBase64EncodedString:encoded options:0];
 return bytes.length>0 && bytes.length<=512;
}
static BOOL save(NSData* data) {
 if(!valid(data)){fprintf(stderr,"AUTH: invalid credential record\n");return NO;}
 NSDictionary* changes=@{(__bridge id)kSecValueData:data,
  (__bridge id)kSecAttrAccessible:(__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly};
 OSStatus status=SecItemUpdate((__bridge CFDictionaryRef)query(),(__bridge CFDictionaryRef)changes);
 if(status==errSecItemNotFound){
  NSMutableDictionary* item=[query() mutableCopy];[item addEntriesFromDictionary:changes];
  status=SecItemAdd((__bridge CFDictionaryRef)item,NULL);
 }
 fprintf(stderr,"AUTH: Keychain save status=%ld\n",(long)status);
 return status==errSecSuccess;
}
static int importPending(void) {
 int fd=open(Inbox,O_RDONLY|O_NOFOLLOW);
 if(fd<0){if(errno==ENOENT)return 0;fprintf(stderr,"AUTH: pending import open failed\n");return -1;}
 struct stat info;
 if(fstat(fd,&info)!=0 || !S_ISREG(info.st_mode) || info.st_uid!=getuid() || (info.st_mode&077)!=0 || info.st_size<1 || info.st_size>4095){
  close(fd);fprintf(stderr,"AUTH: pending import permissions or size invalid\n");return -1;
 }
 char buffer[4096];size_t used=0;
 while(used<sizeof(buffer)){
  ssize_t n=read(fd,buffer+used,sizeof(buffer)-used);
  if(n<0){if(errno==EINTR)continue;close(fd);return -1;}
  if(!n)break;used+=(size_t)n;
 }
 close(fd);
 NSData* data=[NSData dataWithBytes:buffer length:used];memset(buffer,0,sizeof(buffer));
 if(!save(data))return -1;
 if(unlink(Inbox)!=0){fprintf(stderr,"AUTH: pending import cleanup failed\n");return -1;}
 fprintf(stderr,"AUTH: imported credentials into Keychain; temporary inbox removed\n");return 1;
}
int ipad_auth_load(char* output,size_t capacity) {
 @autoreleasepool {
  if(!output || !capacity)return -1;output[0]=0;
  if(importPending()<0)return -1;
  NSMutableDictionary* item=[query() mutableCopy];
  item[(__bridge id)kSecReturnData]=@YES;
  item[(__bridge id)kSecMatchLimit]=(__bridge id)kSecMatchLimitOne;
  CFTypeRef result=NULL;OSStatus status=SecItemCopyMatching((__bridge CFDictionaryRef)item,&result);
  if(status==errSecItemNotFound){fprintf(stderr,"AUTH: no saved account; discovery available\n");return 0;}
  if(status!=errSecSuccess){fprintf(stderr,"AUTH: Keychain load status=%ld\n",(long)status);if(result)CFRelease(result);return -1;}
  NSData* data=CFBridgingRelease(result);
  if(![data isKindOfClass:NSData.class] || !valid(data) || data.length>=capacity)return -1;
  memcpy(output,data.bytes,data.length);output[data.length]=0;
  fprintf(stderr,"AUTH: loaded reusable credentials from Keychain\n");return 1;
 }
}
int ipad_auth_save(const char* json) {
 @autoreleasepool {
  if(!json)return 0;
  return save([[NSString stringWithUTF8String:json] dataUsingEncoding:NSUTF8StringEncoding])?1:0;
 }
}
