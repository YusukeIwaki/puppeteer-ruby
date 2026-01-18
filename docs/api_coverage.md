# API coverages
- Puppeteer version: v20.0.0
- puppeteer-ruby version: 0.45.6

## Puppeteer

* clearCustomQueryHandlers => `#clear_custom_query_handlers`
* connect
* customQueryHandlerNames => `#custom_query_handler_names`
* defaultArgs => `#default_args`
* devices
* ~~errors~~
* executablePath => `#executable_path`
* launch
* networkConditions => `#network_conditions`
* ~~puppeteer~~
* registerCustomQueryHandler => `#register_custom_query_handler`
* unregisterCustomQueryHandler => `#unregister_custom_query_handler`

## ~~Accessibility~~

* ~~snapshot~~

## Browser

* browserContexts => `#browser_contexts`
* close
* createIncognitoBrowserContext => `#create_incognito_browser_context`
* defaultBrowserContext => `#default_browser_context`
* disconnect
* isConnected => `#connected?`
* newPage => `#new_page`
* pages
* process
* target
* targets
* userAgent => `#user_agent`
* version
* waitForTarget => `#wait_for_target`
* wsEndpoint => `#ws_endpoint`

## BrowserContext

* browser
* clearPermissionOverrides => `#clear_permission_overrides`
* close
* cookies
* deleteCookie => `#delete_cookie`
* deleteMatchingCookies => `#delete_matching_cookies`
* isIncognito => `#incognito?`
* newPage => `#new_page`
* overridePermissions => `#override_permissions`
* pages
* setCookie => `#set_cookie`
* targets
* waitForTarget => `#wait_for_target`

## CDPSession

* connection
* detach
* id
* send

## Connection

* createSession => `#create_session`
* dispose
* ~~fromSession~~
* send
* session
* url

## ConsoleMessage

* args
* location
* stackTrace => `#stack_trace`
* text
* ~~type~~

## Coverage

* startCSSCoverage => `#start_css_coverage`
* startJSCoverage => `#start_js_coverage`
* stopCSSCoverage => `#stop_css_coverage`
* stopJSCoverage => `#stop_js_coverage`

## CSSCoverage

* start
* stop

## ~~CustomError~~


## ~~DeviceRequestPrompt~~

* ~~cancel~~
* ~~select~~
* ~~waitForDevice~~

## ~~DeviceRequestPromptDevice~~


## Dialog

* accept
* defaultValue => `#default_value`
* dismiss
* message
* type

## ElementHandle

* $ => `#query_selector`
* $$ => `#query_selector_all`
* $$eval => `#eval_on_selector_all`
* $eval => `#eval_on_selector`
* $x => `#Sx`
* asElement => `#as_element`
* boundingBox => `#bounding_box`
* boxModel => `#box_model`
* click
* clickablePoint => `#clickable_point`
* contentFrame => `#content_frame`
* drag
* dragAndDrop => `#drag_and_drop`
* dragEnter => `#drag_enter`
* dragOver => `#drag_over`
* drop
* focus
* hover
* isHidden => `#hidden?`
* isIntersectingViewport => `#intersecting_viewport?`
* isVisible => `#visible?`
* press
* screenshot
* ~~scrollIntoView~~
* select
* tap
* toElement => `#to_element`
* touchEnd => `#touch_end`
* touchMove => `#touch_move`
* touchStart => `#touch_start`
* type => `#type_text`
* uploadFile => `#upload_file`
* waitForSelector => `#wait_for_selector`
* waitForXPath => `#wait_for_xpath`

## ~~EventEmitter~~

* ~~addListener~~
* ~~emit~~
* ~~listenerCount~~
* ~~off~~
* ~~on~~
* ~~once~~
* ~~removeAllListeners~~
* ~~removeListener~~

## FileChooser

* accept
* cancel
* isMultiple => `#multiple?`

## Frame

* $ => `#query_selector`
* $$ => `#query_selector_all`
* $$eval => `#eval_on_selector_all`
* $eval => `#eval_on_selector`
* $x => `#Sx`
* addScriptTag => `#add_script_tag`
* addStyleTag => `#add_style_tag`
* addStyleTag => `#add_style_tag`
* childFrames => `#child_frames`
* click
* content
* evaluate
* evaluateHandle => `#evaluate_handle`
* focus
* goto
* hover
* isDetached => `#detached?`
* isOOPFrame => `#oop_frame?`
* name
* page
* parentFrame => `#parent_frame`
* select
* setContent => `#set_content`
* tap
* title
* type => `#type_text`
* url
* ~~waitForDevicePrompt~~
* waitForFunction => `#wait_for_function`
* waitForNavigation => `#wait_for_navigation`
* waitForSelector => `#wait_for_selector`
* waitForTimeout => `#wait_for_timeout`
* waitForXPath => `#wait_for_xpath`

## HTTPRequest

* abort
* abortErrorReason => `#abort_error_reason`
* continue
* continueRequestOverrides => `#continue_request_overrides`
* enqueueInterceptAction => `#enqueue_intercept_action`
* failure
* finalizeInterceptions => `#finalize_interceptions`
* frame
* headers
* initiator
* interceptResolutionState => `#intercept_resolution_state`
* isInterceptResolutionHandled => `#intercept_resolution_handled?`
* isNavigationRequest => `#navigation_request?`
* method
* postData => `#post_data`
* redirectChain => `#redirect_chain`
* resourceType => `#resource_type`
* respond
* response
* responseForRequest => `#response_for_request`
* url

## HTTPResponse

* buffer
* frame
* ~~fromCache~~
* ~~fromServiceWorker~~
* headers
* json
* ~~ok~~
* remoteAddress => `#remote_address`
* request
* securityDetails => `#security_details`
* status
* statusText => `#status_text`
* text
* ~~timing~~
* url

## JSCoverage

* start
* stop

## JSHandle

* asElement => `#as_element`
* dispose
* evaluate
* evaluateHandle => `#evaluate_handle`
* getProperties => `#properties`
* getProperty => `#[]`
* getProperty => `#[]`
* getProperty => `#[]`
* jsonValue => `#json_value`
* remoteObject => `#remote_object`
* toString => `#to_s`

## Keyboard

* down
* press
* sendCharacter => `#send_character`
* type => `#type_text`
* up

## Mouse

* click
* down
* drag
* dragAndDrop => `#drag_and_drop`
* dragEnter => `#drag_enter`
* dragOver => `#drag_over`
* drop
* move
* up
* wheel

## Page

* $ => `#query_selector`
* $$ => `#query_selector_all`
* $$eval => `#eval_on_selector_all`
* $eval => `#eval_on_selector`
* $x => `#Sx`
* addScriptTag => `#add_script_tag`
* addStyleTag => `#add_style_tag`
* addStyleTag => `#add_style_tag`
* addStyleTag => `#add_style_tag`
* authenticate
* bringToFront => `#bring_to_front`
* browser
* browserContext => `#browser_context`
* click
* close
* content
* cookies
* createPDFStream => `#create_pdf_stream`
* deleteCookie => `#delete_cookie`
* emulate
* emulateCPUThrottling => `#emulate_cpu_throttling`
* emulateIdleState => `#emulate_idle_state`
* emulateMediaFeatures => `#emulate_media_features`
* emulateMediaType => `#emulate_media_type`
* emulateNetworkConditions => `#emulate_network_conditions`
* emulateTimezone => `#emulate_timezone`
* emulateVisionDeficiency => `#emulate_vision_deficiency`
* evaluate
* evaluateHandle => `#evaluate_handle`
* evaluateOnNewDocument => `#evaluate_on_new_document`
* exposeFunction => `#expose_function`
* focus
* frames
* ~~getDefaultTimeout~~
* goBack => `#go_back`
* goForward => `#go_forward`
* goto
* hover
* isClosed => `#closed?`
* isDragInterceptionEnabled => `#drag_interception_enabled?`
* isJavaScriptEnabled => `#javascript_enabled?`
* mainFrame => `#main_frame`
* metrics
* off
* on
* once
* pdf
* queryObjects => `#query_objects`
* reload
* screenshot
* screenshot
* screenshot
* select
* setBypassCSP => `#bypass_csp=`
* setCacheEnabled => `#cache_enabled=`
* setContent => `#content=`
* setCookie => `#set_cookie`
* setDefaultNavigationTimeout => `#default_navigation_timeout=`
* setDefaultTimeout => `#default_timeout=`
* ~~setDragInterception~~
* setExtraHTTPHeaders => `#extra_http_headers=`
* setGeolocation => `#geolocation=`
* setJavaScriptEnabled => `#javascript_enabled=`
* setOfflineMode => `#offline_mode=`
* setRequestInterception => `#request_interception=`
* setUserAgent => `#user_agent=`
* setViewport => `#viewport=`
* tap
* target
* title
* type => `#type_text`
* url
* viewport
* ~~waitForDevicePrompt~~
* waitForFileChooser => `#wait_for_file_chooser`
* waitForFrame => `#wait_for_frame`
* waitForFunction => `#wait_for_function`
* waitForNavigation => `#wait_for_navigation`
* waitForNetworkIdle => `#wait_for_network_idle`
* waitForRequest => `#wait_for_request`
* waitForResponse => `#wait_for_response`
* waitForSelector => `#wait_for_selector`
* waitForTimeout => `#wait_for_timeout`
* waitForXPath => `#wait_for_xpath`
* workers

## ~~ProductLauncher~~

* ~~defaultArgs~~
* ~~executablePath~~
* ~~launch~~

## ~~ProtocolError~~


## ~~SecurityDetails~~

* ~~issuer~~
* ~~protocol~~
* ~~subjectAlternativeNames~~
* ~~subjectName~~
* ~~validFrom~~
* ~~validTo~~

## Target

* browser
* browserContext => `#browser_context`
* createCDPSession => `#create_cdp_session`
* opener
* page
* type
* url
* ~~worker~~

## TimeoutError


## Touchscreen

* tap
* touchEnd => `#touch_end`
* touchMove => `#touch_move`
* touchStart => `#touch_start`

## Tracing

* start
* stop

## WebWorker

* evaluate
* evaluateHandle => `#evaluate_handle`
* url
