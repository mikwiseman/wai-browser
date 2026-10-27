#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>
#include "include/cef_app.h"
#include "include/cef_application_mac.h"
#include "include/cef_command_line.h"
#include "include/cef_command_ids.h"
#include "include/wrapper/cef_closure_task.h"
#include "include/base/cef_bind.h"
#include "include/base/cef_callback.h"
#include "../shared/WAISite.h"
#include "include/cef_parser.h"
#include "include/cef_request_context.h"
#include "include/wrapper/cef_helpers.h"
#include "include/wrapper/cef_library_loader.h"
#include "trust.h"
#include <algorithm>
#include <cstdlib>
#include <cerrno>
#include <limits.h>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>

static std::string g_profile;
static wai::TrustConfig g_trust;
static wai::TrustConfig g_appliedTrust;
static bool g_restart=false;
static bool g_restartInBackground=false;
static NSMutableArray<NSString*>* g_restoreURLs;

static NSString* StartURL() {return [[[NSBundle mainBundle] URLForResource:@"start" withExtension:@"html"] absoluteString];}
static NSString* Site(NSString* value) {return WAISiteFromInput(value,[NSBundle.mainBundle.resourcePath stringByAppendingPathComponent:@"public_suffix_list.dat"]);}
static bool NeedsRestart() {return g_trust.enabled!=g_appliedTrust.enabled || g_trust.domains!=g_appliedTrust.domains;}

@interface WaiDelegate : NSObject <NSApplicationDelegate,NSWindowDelegate,NSTableViewDataSource,NSTableViewDelegate>
@property(strong) NSWindow* settingsWindow;
@property(strong) NSButton* enabled;
@property(strong) NSTableView* sites;
@property(strong) NSTextField* siteField;
@property(strong) NSButton* currentSite;
@property(copy) NSString* currentDomain;
@property(strong) NSButton* removeButton;
@property(strong) NSTextField* status;
@property(strong) NSButton* restartButton;
@property(strong) SPUStandardUpdaterController* updater;
- (void)installMenu;
- (void)showSettings:(id)sender;
- (void)finishSettings:(id)sender;
- (void)restart:(id)sender;
- (void)quit:(id)sender;
@end
static WaiDelegate* g_delegate;

class BrowserClient final : public CefClient, public CefLifeSpanHandler, public CefFocusHandler, public CefJSDialogHandler {
 public:
  std::vector<CefRefPtr<CefBrowser>> browsers;
  CefRefPtr<CefBrowser> active;
  CefRefPtr<CefLifeSpanHandler> GetLifeSpanHandler() override {return this;}
  CefRefPtr<CefFocusHandler> GetFocusHandler() override {return this;}
  CefRefPtr<CefJSDialogHandler> GetJSDialogHandler() override {return this;}
  void OnGotFocus(CefRefPtr<CefBrowser> browser) override {active=browser;}
  void OnAfterCreated(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();browsers.push_back(browser);active=browser;[g_delegate installMenu];
    if(g_restoreURLs.count) {
      NSString* url=g_restoreURLs.firstObject;[g_restoreURLs removeObjectAtIndex:0];
      browser->GetMainFrame()->LoadURL(url.UTF8String);
      if(g_restoreURLs.count)CefPostTask(TID_UI,CefCreateClosureTask(base::BindOnce([](CefRefPtr<CefBrowser> b){b->GetHost()->ExecuteChromeCommand(IDC_NEW_TAB,CEF_WOD_NEW_FOREGROUND_TAB);},browser)));
    }
  }
  void OnBeforeClose(CefRefPtr<CefBrowser> browser) override {
    CEF_REQUIRE_UI_THREAD();
    std::erase_if(browsers,[&](auto b){return b->IsSame(browser);});
    if(active&&active->IsSame(browser))active=browsers.empty()?nullptr:browsers.back();
    if(browsers.empty())CefQuitMessageLoop();
  }
  bool OnBeforeUnloadDialog(CefRefPtr<CefBrowser>,const CefString&,bool,CefRefPtr<CefJSDialogCallback> callback) override {
    if(!g_restart)return false;
    NSAlert* alert=[NSAlert new];alert.messageText=@"На странице есть несохранённые изменения";
    alert.informativeText=@"Продолжить перезапуск? Несохранённый текст может быть потерян.";
    [alert addButtonWithTitle:@"Остаться"];[alert addButtonWithTitle:@"Перезапустить"];
    bool leave=[alert runModal]==NSAlertSecondButtonReturn;
    if(!leave){g_restart=false;[[NSFileManager defaultManager] removeItemAtPath:[@(g_profile.c_str()) stringByAppendingPathComponent:@"restart-tabs.json"] error:nil];}
    callback->Continue(leave,{});return true;
  }
  void CloseAll(){auto copy=browsers;for(auto browser:copy)browser->GetHost()->CloseBrowser(false);}
 private:
  IMPLEMENT_REFCOUNTING(BrowserClient);
};
static CefRefPtr<BrowserClient> g_client;

class BrowserApp final : public CefApp, public CefBrowserProcessHandler {
 public:
  CefRefPtr<CefBrowserProcessHandler> GetBrowserProcessHandler() override{return this;}
  void OnContextInitialized() override {
    CEF_REQUIRE_UI_THREAD();g_client=new BrowserClient;
    auto command=CefCommandLine::GetGlobalCommandLine();
    if(command->HasSwitch("restore-wai-tabs")) {
      NSString* path=[@(g_profile.c_str()) stringByAppendingPathComponent:@"restart-tabs.json"];
      NSData* data=[NSData dataWithContentsOfFile:path];
      id urls=data?[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil]:nil;
      if([urls isKindOfClass:NSMutableArray.class])g_restoreURLs=urls;
      [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
      for(NSUInteger i=0;i<g_restoreURLs.count;++i)if([g_restoreURLs[i] isEqual:@"wai:start"])g_restoreURLs[i]=StartURL();
    }
    std::string url=command->GetSwitchValue("url");
    if(url.empty())url=StartURL().UTF8String;
    CefWindowInfo window;window.runtime_style=CEF_RUNTIME_STYLE_CHROME;
    CefBrowserSettings settings;
    CefBrowserHost::CreateBrowser(window,g_client,url,settings,nullptr,nullptr);
  }
  CefRefPtr<CefClient> GetDefaultClient() override{return g_client;}
 private:
  IMPLEMENT_REFCOUNTING(BrowserApp);
};

@interface WaiApplication : NSApplication <CefAppProtocol>
@property(nonatomic) BOOL handlingSendEvent;
@end
@implementation WaiApplication
- (BOOL)isHandlingSendEvent{return self.handlingSendEvent;}
- (void)sendEvent:(NSEvent*)event {CefScopedSendingEvent scope;[super sendEvent:event];}
- (void)terminate:(id)sender {[g_delegate quit:sender];}
@end

@interface WaiSettingsWindow : NSWindow
@end
@implementation WaiSettingsWindow
- (void)cancelOperation:(id)sender {[g_delegate finishSettings:sender];}
- (BOOL)performKeyEquivalent:(NSEvent*)event {
  if((event.modifierFlags&NSEventModifierFlagCommand)&&[event.charactersIgnoringModifiers.lowercaseString isEqual:@"w"]){[g_delegate finishSettings:nil];return YES;}
  return [super performKeyEquivalent:event];
}
@end

@implementation WaiDelegate
- (void)browserCommand:(NSMenuItem*)sender {
  if(g_client&&g_client->active)g_client->active->GetHost()->ExecuteChromeCommand((int)sender.tag,CEF_WOD_CURRENT_TAB);
}
- (void)closeContext:(id)sender {
  if(NSApp.keyWindow==self.settingsWindow){[self finishSettings:sender];return;}
  if(g_client&&g_client->active)g_client->active->GetHost()->ExecuteChromeCommand(IDC_CLOSE_TAB,CEF_WOD_CURRENT_TAB);
}
- (void)undo:(id)sender {if(g_client&&g_client->active)g_client->active->GetFocusedFrame()->Undo();}
- (void)redo:(id)sender {if(g_client&&g_client->active)g_client->active->GetFocusedFrame()->Redo();}
- (void)cut:(id)sender {if(g_client&&g_client->active)g_client->active->GetHost()->ExecuteChromeCommand(IDC_CUT,CEF_WOD_CURRENT_TAB);}
- (void)copy:(id)sender {if(g_client&&g_client->active)g_client->active->GetHost()->ExecuteChromeCommand(IDC_COPY,CEF_WOD_CURRENT_TAB);}
- (void)paste:(id)sender {if(g_client&&g_client->active)g_client->active->GetHost()->ExecuteChromeCommand(IDC_PASTE,CEF_WOD_CURRENT_TAB);}
- (void)selectAll:(id)sender {if(g_client&&g_client->active)g_client->active->GetFocusedFrame()->SelectAll();}
- (void)installMenu {
  NSMenu* menu=NSApp.mainMenu;if(!menu||[menu itemWithTitle:@"WAI"])return;
  NSMenuItem* applicationItem=[menu itemAtIndex:0];
  if(!applicationItem.submenu)applicationItem.submenu=[[NSMenu alloc] initWithTitle:@"Wai Browser"];
  NSMenuItem* quit=[applicationItem.submenu addItemWithTitle:@"Завершить Wai Browser" action:@selector(quit:) keyEquivalent:@"q"];
  quit.target=self;
  NSMenuItem* item=[[NSMenuItem alloc] initWithTitle:@"WAI" action:nil keyEquivalent:@""];
  NSMenu* submenu=[[NSMenu alloc] initWithTitle:@"WAI"];
  NSMenuItem* settings=[submenu addItemWithTitle:@"Сертификаты…" action:@selector(showSettings:) keyEquivalent:@","];
  settings.target=self;
  [submenu addItem:NSMenuItem.separatorItem];
  NSMenuItem* update=[submenu addItemWithTitle:@"Проверить обновления…" action:@selector(checkForUpdates:) keyEquivalent:@""];
  update.target=self;
  item.submenu=submenu;[menu insertItem:item atIndex:1];
  NSMenuItem* file=[NSMenuItem new];file.title=@"Файл";file.submenu=[[NSMenu alloc] initWithTitle:file.title];[menu addItem:file];
  NSMenuItem* view=[NSMenuItem new];view.title=@"Вид";view.submenu=[[NSMenu alloc] initWithTitle:view.title];[menu addItem:view];
  auto commandItem=[&](NSMenu* parent,NSString* title,NSString* key,NSInteger command,NSEventModifierFlags modifiers=NSEventModifierFlagCommand){
    NSMenuItem* commandMenu=[parent addItemWithTitle:title action:@selector(browserCommand:) keyEquivalent:(modifiers&NSEventModifierFlagShift)?key.uppercaseString:key];
    commandMenu.target=self;commandMenu.tag=command;commandMenu.keyEquivalentModifierMask=modifiers;
  };
  commandItem(file.submenu,@"Новая вкладка",@"t",IDC_NEW_TAB);
  commandItem(file.submenu,@"Новое окно",@"n",IDC_NEW_WINDOW);
  commandItem(file.submenu,@"Вернуть закрытую вкладку",@"t",IDC_RESTORE_TAB,NSEventModifierFlagCommand|NSEventModifierFlagShift);
  NSMenuItem* close=[file.submenu addItemWithTitle:@"Закрыть" action:@selector(closeContext:) keyEquivalent:@"w"];close.target=self;
  commandItem(file.submenu,@"Сохранить страницу…",@"s",IDC_SAVE_PAGE);
  commandItem(file.submenu,@"Печать…",@"p",IDC_PRINT);
  commandItem(view.submenu,@"Адресная строка",@"l",IDC_FOCUS_LOCATION);
  commandItem(view.submenu,@"Обновить",@"r",IDC_RELOAD);
  commandItem(view.submenu,@"Обновить без кэша",@"r",IDC_RELOAD_BYPASSING_CACHE,NSEventModifierFlagCommand|NSEventModifierFlagShift);
  commandItem(view.submenu,@"Назад",@"[",IDC_BACK);
  commandItem(view.submenu,@"Вперёд",@"]",IDC_FORWARD);
  commandItem(view.submenu,@"Следующая вкладка",@"\t",IDC_SELECT_NEXT_TAB,NSEventModifierFlagControl);
  commandItem(view.submenu,@"Предыдущая вкладка",@"\t",IDC_SELECT_PREVIOUS_TAB,NSEventModifierFlagControl|NSEventModifierFlagShift);
  for(int i=0;i<9;++i)commandItem(view.submenu,[NSString stringWithFormat:@"Вкладка %d",i+1],[@(i+1) stringValue],i==8?IDC_SELECT_LAST_TAB:IDC_SELECT_TAB_0+i);
  commandItem(view.submenu,@"Увеличить",@"+",IDC_ZOOM_PLUS);
  commandItem(view.submenu,@"Уменьшить",@"-",IDC_ZOOM_MINUS);
  commandItem(view.submenu,@"Исходный масштаб",@"0",IDC_ZOOM_NORMAL);
  if(![menu itemWithTitle:@"Правка"]){
    NSMenuItem* edit=[NSMenuItem new];edit.title=@"Правка";
    NSMenu* items=[[NSMenu alloc] initWithTitle:@"Правка"];
    [items addItemWithTitle:@"Отменить" action:@selector(undo:) keyEquivalent:@"z"];
    NSMenuItem* redo=[items addItemWithTitle:@"Повторить" action:@selector(redo:) keyEquivalent:@"Z"];redo.keyEquivalentModifierMask=NSEventModifierFlagCommand|NSEventModifierFlagShift;
    [items addItem:NSMenuItem.separatorItem];
    [items addItemWithTitle:@"Вырезать" action:@selector(cut:) keyEquivalent:@"x"];
    [items addItemWithTitle:@"Копировать" action:@selector(copy:) keyEquivalent:@"c"];
    [items addItemWithTitle:@"Вставить" action:@selector(paste:) keyEquivalent:@"v"];
    [items addItemWithTitle:@"Выбрать всё" action:@selector(selectAll:) keyEquivalent:@"a"];
    commandItem(items,@"Найти…",@"f",IDC_FIND);
    edit.submenu=items;[menu addItem:edit];
  }
  // No startup network request until a real release feed has been configured.
  NSString* feed=[[NSBundle mainBundle] objectForInfoDictionaryKey:@"SUFeedURL"];
  if(feed.length && !self.updater){
    self.updater=[[SPUStandardUpdaterController alloc] initWithStartingUpdater:YES updaterDelegate:nil userDriverDelegate:nil];
  }
}
- (void)checkForUpdates:(id)sender {
  if(self.updater){[self.updater checkForUpdates:sender];return;}
  NSAlert* alert=[NSAlert new];alert.messageText=@"Канал обновлений ещё не опубликован";
  alert.informativeText=@"В этой сборке проверка обновлений пока недоступна.";[alert runModal];
}
- (void)refreshSettings {
  self.enabled.state=g_trust.enabled?NSControlStateValueOn:NSControlStateValueOff;
  [self.sites reloadData];self.removeButton.enabled=self.sites.selectedRow>=0;
  self.restartButton.hidden=!NeedsRestart();
  self.status.stringValue=NeedsRestart()?@"Сохранено. Примените изменения перезапуском.":@"Обычная проверка сертификатов на остальных сайтах.";
}
- (BOOL)store:(wai::TrustConfig)next {
  if(!wai::SaveConfig(g_profile+"/trust.json",next)){self.status.stringValue=@"Не удалось сохранить. Попробуйте ещё раз.";return NO;}
  g_trust=next;[self refreshSettings];return YES;
}
- (NSInteger)numberOfRowsInTableView:(NSTableView*)table {return g_trust.domains.size();}
- (NSView*)tableView:(NSTableView*)table viewForTableColumn:(NSTableColumn*)column row:(NSInteger)row {
  NSTextField* label=[NSTextField labelWithString:@(g_trust.domains[row].c_str())];
  label.font=[NSFont systemFontOfSize:14];label.accessibilityLabel=label.stringValue;return label;
}
- (void)tableViewSelectionDidChange:(NSNotification*)notification {self.removeButton.enabled=self.sites.selectedRow>=0;}
- (void)toggleTrust:(id)sender {auto next=g_trust;next.enabled=self.enabled.state==NSControlStateValueOn;[self store:next];}
- (void)addSite:(id)sender {
  NSString* site=Site(self.siteField.stringValue);
  if(!site){self.status.stringValue=@"Вставьте адрес сайта, например https://rzd.ru";return;}
  auto next=g_trust;std::string domain=site.UTF8String;
  if(std::find(next.domains.begin(),next.domains.end(),domain)==next.domains.end())next.domains.push_back(domain);
  if([self store:next]){self.siteField.stringValue=@"";[self.settingsWindow makeFirstResponder:self.siteField];}
}
- (void)addCurrentSite:(id)sender {self.siteField.stringValue=self.currentDomain;[self addSite:sender];}
- (void)removeSite:(id)sender {
  NSInteger row=self.sites.selectedRow;if(row<0||row>=(NSInteger)g_trust.domains.size())return;
  auto next=g_trust;next.domains.erase(next.domains.begin()+row);[self store:next];
}
- (void)showSettings:(id)sender {
  if(!self.settingsWindow){
    self.settingsWindow=[[WaiSettingsWindow alloc] initWithContentRect:NSMakeRect(0,0,560,454) styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self.settingsWindow.title=@"Сертификаты";self.settingsWindow.releasedWhenClosed=NO;self.settingsWindow.delegate=self;[self.settingsWindow center];
    NSView* content=self.settingsWindow.contentView;
    NSTextField* title=[NSTextField labelWithString:@"Сертификаты для сайтов"];
    title.font=[NSFont systemFontOfSize:22 weight:NSFontWeightSemibold];title.frame=NSMakeRect(24,390,512,34);[content addSubview:title];
    NSTextField* description=[NSTextField wrappingLabelWithString:@"Российские сертификаты только для сайтов из списка и их поддоменов. Только внутри Wai Browser."];
    description.textColor=NSColor.secondaryLabelColor;description.frame=NSMakeRect(24,344,512,40);[content addSubview:description];
    self.enabled=[NSButton checkboxWithTitle:@"Российские сертификаты" target:self action:@selector(toggleTrust:)];self.enabled.frame=NSMakeRect(24,310,512,28);[content addSubview:self.enabled];
    self.siteField=[[NSTextField alloc] initWithFrame:NSMakeRect(24,270,392,28)];self.siteField.placeholderString=@"Адрес сайта или ссылка";self.siteField.accessibilityLabel=@"Адрес сайта";self.siteField.target=self;self.siteField.action=@selector(addSite:);[content addSubview:self.siteField];
    NSButton* add=[NSButton buttonWithTitle:@"Добавить" target:self action:@selector(addSite:)];add.frame=NSMakeRect(424,267,112,32);[content addSubview:add];
    self.currentSite=[NSButton buttonWithTitle:@"Добавить текущий сайт" target:self action:@selector(addCurrentSite:)];self.currentSite.frame=NSMakeRect(24,230,512,30);[content addSubview:self.currentSite];
    NSScrollView* scroll=[[NSScrollView alloc] initWithFrame:NSMakeRect(24,100,512,120)];scroll.borderType=NSBezelBorder;scroll.hasVerticalScroller=YES;
    self.sites=[[NSTableView alloc] initWithFrame:scroll.bounds];NSTableColumn* column=[[NSTableColumn alloc] initWithIdentifier:@"site"];column.width=480;[self.sites addTableColumn:column];self.sites.headerView=nil;self.sites.rowHeight=28;self.sites.dataSource=self;self.sites.delegate=self;self.sites.accessibilityLabel=@"Сайты с российскими сертификатами";scroll.documentView=self.sites;[content addSubview:scroll];
    self.removeButton=[NSButton buttonWithTitle:@"Удалить выбранный" target:self action:@selector(removeSite:)];self.removeButton.frame=NSMakeRect(20,64,174,30);[content addSubview:self.removeButton];
    self.status=[NSTextField labelWithString:@""];self.status.font=[NSFont systemFontOfSize:11];self.status.textColor=NSColor.secondaryLabelColor;self.status.frame=NSMakeRect(24,43,512,16);[content addSubview:self.status];
    self.restartButton=[NSButton buttonWithTitle:@"Перезапустить" target:self action:@selector(restart:)];self.restartButton.frame=NSMakeRect(258,7,160,32);[content addSubview:self.restartButton];
    NSButton* done=[NSButton buttonWithTitle:@"Готово" target:self action:@selector(finishSettings:)];done.frame=NSMakeRect(426,7,110,32);done.keyEquivalent=@"\r";[content addSubview:done];
  }
  NSString* current=g_client&&g_client->active?Site(@(g_client->active->GetMainFrame()->GetURL().ToString().c_str())):nil;
  self.currentDomain=current;self.currentSite.enabled=current!=nil;
  self.currentSite.title=current?[@"Добавить " stringByAppendingString:current]:@"Откройте сайт, чтобы добавить его здесь";
  [self refreshSettings];[self.settingsWindow makeKeyAndOrderFront:nil];
}
- (BOOL)windowShouldClose:(NSWindow*)window {[self finishSettings:nil];return NO;}
- (void)finishSettings:(id)sender {
  if(self.siteField.stringValue.length){[self addSite:nil];if(self.siteField.stringValue.length)return;}
  if(!NeedsRestart()){[self.settingsWindow orderOut:nil];return;}
  NSAlert* alert=[NSAlert new];alert.messageText=@"Применить настройки сертификатов?";
  alert.informativeText=@"Wai Browser перезапустится и откроет ваши вкладки. Несохранённые формы могут потребовать подтверждения.";
  [alert addButtonWithTitle:@"Перезапустить"];[alert addButtonWithTitle:@"Позже"];
  [alert beginSheetModalForWindow:self.settingsWindow completionHandler:^(NSModalResponse response){
    [self.settingsWindow orderOut:nil];if(response==NSAlertFirstButtonReturn)[self restart:nil];
  }];
}
- (void)restart:(id)sender {
  if(g_restart||!g_client)return;
  NSMutableArray* urls=[NSMutableArray array];
  for(auto browser:g_client->browsers){NSString* url=@(browser->GetMainFrame()->GetURL().ToString().c_str());[urls addObject:[url isEqual:StartURL()]?@"wai:start":url];}
  NSData* data=[NSJSONSerialization dataWithJSONObject:urls options:0 error:nil];
  if(![data writeToFile:[@(g_profile.c_str()) stringByAppendingPathComponent:@"restart-tabs.json"] options:NSDataWritingAtomic error:nil]){self.status.stringValue=@"Не удалось сохранить вкладки. Перезапуск отменён.";return;}
  g_restart=true;g_restartInBackground=!NSApp.isActive;[self.settingsWindow orderOut:nil];g_client->CloseAll();
}
- (void)quit:(id)sender {
  if(g_client)g_client->CloseAll();else CefQuitMessageLoop();
}
- (BOOL)applicationSupportsSecureRestorableState:(NSApplication*)app{return YES;}
@end

int main(int argc,char* argv[]) {
  CefScopedLibraryLoader loader;if(!loader.LoadInMain())return 1;
  @autoreleasepool {
    [WaiApplication sharedApplication];
    CefRefPtr<CefCommandLine> command=CefCommandLine::CreateCommandLine();command->InitFromArgv(argc,argv);
    g_profile=command->GetSwitchValue("user-data-dir");
    if(g_profile.empty())g_profile=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/Wai Browser"].UTF8String;
    if(![[NSFileManager defaultManager] createDirectoryAtPath:[NSString stringWithUTF8String:g_profile.c_str()] withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil])return 1;
    char resolved[PATH_MAX];if(realpath(g_profile.c_str(),resolved))g_profile=resolved;
    g_trust=wai::LoadConfig(g_profile+"/trust.json");g_appliedTrust=g_trust;
    std::string resources=NSBundle.mainBundle.resourcePath.UTF8String;
    auto root=wai::ReadBytes(resources+"/certificates/root.der");
    std::vector<wai::Bytes> intermediates={wai::ReadBytes(resources+"/certificates/intermediate.der"),wai::ReadBytes(resources+"/certificates/intermediate-2024.der")};
    int profileLock=open((g_profile+"/.wai.lock").c_str(),O_RDWR|O_CREAT,0600);
    if(profileLock<0)return 1;
    bool ownProfile=flock(profileLock,LOCK_EX|LOCK_NB)==0;
    if(!ownProfile&&errno!=EWOULDBLOCK&&errno!=EAGAIN){close(profileLock);return 1;}
    if(ownProfile&&!wai::SyncProfileTrust(g_profile,g_trust,root,intermediates)){
      NSAlert* alert=[NSAlert new];alert.messageText=@"Не удалось настроить сертификаты";
      alert.informativeText=@"Хранилище профиля занято или его формат изменился. Браузер не запущен. Проверьте обновление Wai Browser.";
      [alert runModal];close(profileLock);return 1;
    }
    CefSettings settings;CefString(&settings.root_cache_path)=g_profile;CefString(&settings.cache_path)=g_profile+"/Default";
    settings.persist_session_cookies=true;settings.log_severity=LOGSEVERITY_ERROR;
    CefString(&settings.log_file)=g_profile+"/browser.log";
    CefString(&settings.locale)="ru";CefString(&settings.accept_language_list)="ru,en-US,en";
    CefMainArgs args(argc,argv);CefRefPtr<BrowserApp> app=new BrowserApp;
    if(!CefInitialize(args,settings,app,nullptr))return CefGetExitCode();
    g_delegate=[WaiDelegate new];NSApp.delegate=g_delegate;
    CefRunMessageLoop();g_client=nullptr;CefShutdown();close(profileLock);g_delegate=nil;
    if(g_restart) {
      NSMutableArray* arguments=[NSMutableArray arrayWithObject:@"-n"];if(g_restartInBackground)[arguments addObject:@"-g"];
      [arguments addObject:NSBundle.mainBundle.bundlePath];[arguments addObject:@"--args"];
      for(int i=1;i<argc;++i){NSString* arg=@(argv[i]);if(![arg hasPrefix:@"--url="]&&![arg isEqual:@"--restore-wai-tabs"])[arguments addObject:arg];}
      [arguments addObject:[@"--user-data-dir=" stringByAppendingString:@(g_profile.c_str())]];[arguments addObject:@"--restore-wai-tabs"];
      NSTask* launch=[NSTask new];launch.executableURL=[NSURL fileURLWithPath:@"/usr/bin/open"];launch.arguments=arguments;
      NSError* error=nil;if(![launch launchAndReturnError:&error])NSLog(@"Restart failed: %@",error);
    }
  }
  return 0;
}
