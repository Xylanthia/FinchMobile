#pragma once
#include <stddef.h>
#include <stdint.h>

namespace ariaui {
enum Group : uint8_t { MODES, WIFI, BLE, SUBGHZ, LORA, DRAGON, TRACK, CAPTURES, LINK, LOGS, SYSTEM, GROUP_COUNT };
enum Input : uint8_t { NONE, TEXT, NUMBER, MAC, HEX_INPUT, WIFI_JOIN, COMMAND };
struct Tool { const char* name; const char* detail; uint16_t color; };
struct Action {
  Group group;
  const char* label;
  const char* detail;
  const char* command;
  Input input;
  const char* choices;
  bool confirm;
};
static constexpr Tool tools[] = {
 {"Modes", "All tools and operating modes",0x07FF},
 {"Wi-Fi", "Channels, devices and frame evidence",0x07FF},
 {"Bluetooth", "Scan, filter and advertising evidence",0xA55F},
 {"Sub-GHz", "Capture / select / confirm raw TX",0x07FF},
 {"LoRa (later)", "Deferred; focus on Wi-Fi / BLE / Sub-GHz",0x07D0},
 {"Dragon", "Radio selection and target controls",0xF9AB},
 {"Track", "Selected devices and sighting scenes",0xFD68},
 {"Capture review", "Raw signals, target evidence and replay samples",0x07D0},
 {"Long range", "ESP-NOW peer, messages and link test",0x07FF},
 {"Session", "Save, inspect and export evidence",0xFD68},
 {"Device", "Health, connectivity and commands",0xA55F}
};
#define RUN(g,l,d,c) {g,l,d,c,NONE,nullptr,false}
#define EDIT(g,l,d,c,i) {g,l,d,c,i,nullptr,false}
#define PICK(g,l,d,c,i,p) {g,l,d,c,i,p,false}
#define ASK(g,l,d,c) {g,l,d,c,NONE,nullptr,true}
static constexpr Action actions[] = {
 RUN(CAPTURES,"UAS Remote ID","Validated RID list, flight, RF and raw evidence","ui.uas"),
 RUN(MODES,"Recon","Wi-Fi / BLE / radio discovery","./aria mode recon"),
 RUN(MODES,"Dragon","BLE research and radio controls","./aria mode dragon"),
 RUN(MODES,"Track","Asset and alert monitoring","./aria mode track"),
 RUN(MODES,"Wi-Fi","All Wi-Fi tools","ui.group 1"),
 RUN(MODES,"Bluetooth","Scanning, filters and original evidence","ui.group 2"),
 RUN(MODES,"Sub-GHz","Capture, decode and replay tools","ui.group 3"),
 RUN(MODES,"UAS Remote ID","Flight, radio and raw evidence","ui.uas"),
 RUN(MODES,"Capture review","All retained capture types","ui.group 7"),
 RUN(MODES,"Long range","Peer, messages and link status","ui.group 8"),
 RUN(MODES,"Session","Save, inspect and download all outputs","ui.group 9"),
 RUN(MODES,"Device","Health, connectivity and settings","ui.group 10"),
 RUN(MODES,"LoRa (later)","Unavailable on ARIA in this build","ui.group 4"),
 RUN(WIFI,"Deauth lab","Select or enter a lab MAC; ARIA AP clients only","ui.wifideauth"),
 EDIT(WIFI,"Set deauth MAC","Enter a runtime lab target MAC","ui.wifitarget %s",MAC),
 RUN(WIFI,"Block lab client","Remove one ARIA AP client on rejoin until Unblock","ui.wifiblock"),
 RUN(WIFI,"Unblock lab client","Allow the blocked ARIA AP client to reconnect","./aria wifi lab-disconnect unblock"),
 EDIT(WIFI,"Block MAC","Enter one MAC currently connected to ARIA AP","./aria wifi lab-disconnect prepare-block %s",MAC),
 RUN(WIFI,"Lab disconnect","Select one client connected to ARIA AP; confirmation required","ui.wifidisconnect"),
 RUN(WIFI,"Lab client status","Connected AP clients and one-shot test status","./aria wifi lab-disconnect status"),
 RUN(WIFI,"Start scanning","Resume reception","./aria start"),
 RUN(WIFI,"Stop scanning","Pause and save session snapshot","./aria stop"),
 RUN(WIFI,"Device list","Browse nearby Wi-Fi devices","ui.devices"),
 PICK(WIFI,"Channel","Select channel 1 through 11","./aria wifi channel %s",NUMBER,"1|2|3|4|5|6|7|8|9|10|11"),
 RUN(WIFI,"Hop channels","Visit all Wi-Fi channels","./aria wifi channel hop"),
 RUN(WIFI,"Hold channel","Disable channel hopping","./aria wifi channel fixed"),
 RUN(WIFI,"EAPOL statistics","Observed frames, not verified handshakes","./aria wifi handshake"),
 RUN(WIFI,"Deauth observations","Observed disconnect frames","./aria wifi deauth"),
 RUN(WIFI,"Frame evidence","Retained original Wi-Fi frames","./aria wifi frames limit 4"),
 RUN(WIFI,"EAPOL evidence","Retained original EAPOL frames","./aria wifi handshakes limit 4"),
 RUN(WIFI,"Channel activity","Observed Wi-Fi frames by channel","./aria intel wifi all 5"),
 RUN(WIFI,"MITM proxy","AP-to-upstream HTTP and CONNECT relay","./aria wifi mitm start"),
 EDIT(WIFI,"MITM upstream","Connect upstream SSID and password","./aria wifi mitm upstream \"%s\" \"%s\"",WIFI_JOIN),
 EDIT(WIFI,"MITM AP name","Name of the client-facing lab AP","./aria wifi mitm ap \"%s\"",TEXT),
 RUN(WIFI,"MITM status","Clients, destinations and relayed bytes","./aria wifi mitm status"),
 RUN(WIFI,"Stop MITM","Close relay and restore scanning","./aria wifi mitm stop"),
 RUN(WIFI,"Attempt M1-M4","Capture sweep for all observed AP/client sources","./aria wifi capture all"),
 RUN(WIFI,"Capture progress","Per-device sweep and exchange counts","./aria wifi capture status"),
 RUN(WIFI,"Stop capture sweep","Return to normal channel hopping","./aria wifi capture stop"),
 RUN(BLE,"Start scanning","Receive advertisements","./aria ble scan on"),
 RUN(BLE,"Stop scanning","Pause advertisement scanning","./aria ble scan off"),
 RUN(BLE,"Nearby devices","Names, vendors and signal strength","ui.devices"),
 EDIT(BLE,"Name filter","Enter a device name","./aria ble filter \"%s\"",TEXT),
 RUN(BLE,"Clear filter","Show all BLE devices","./aria ble filter clear"),
 RUN(BLE,"Original evidence","Retained advertisement bytes","./aria evidence ble limit 4"),
 RUN(SUBGHZ,"TX / Replay sample","Select complete raw sample, then confirm transmission","ui.replay"),
 RUN(SUBGHZ,"Cancel TX","Clear prepared transmission","./aria subghz tx cancel"),
 RUN(SUBGHZ,"Live waveform","Original retained signal levels","ui.wave"),
 RUN(SUBGHZ,"Packet intel","Decoded identity, fields and evidence","ui.subghzintel"),
 RUN(SUBGHZ,"Start reception","Enable CC1101 receiver","./aria subghz scan on"),
 RUN(SUBGHZ,"Stop reception","Pause CC1101 receiver","./aria subghz scan off"),
 PICK(SUBGHZ,"Lock band","Park on one frequency","./aria subghz freq %s",NUMBER,"315|433|868|915"),
 RUN(SUBGHZ,"Hop bands","315 / 433 / 868 / 915 MHz","./aria subghz hop"),
 PICK(SUBGHZ,"Hop dwell","Time per band in milliseconds","./aria subghz hop %s",NUMBER,"400|900|2000|5000|10000"),
 RUN(SUBGHZ,"Dwell table","Inspect per-band park times","./aria subghz dwell"),
 EDIT(SUBGHZ,"Custom band dwell","Example: 433 5000","./aria subghz dwell %s",TEXT),
 RUN(SUBGHZ,"Received packets","Recent capture summaries","./aria subghz list"),
 RUN(SUBGHZ,"Latest raw capture","Event/frame identity and full raw replay HEX","ui.raw"),
 PICK(SUBGHZ,"Raw history","Choose number of recent captures","./aria subghz raw %s",NUMBER,"1|5|10|25|50"),
 RUN(SUBGHZ,"Payload formats","HEX / bits / ASCII / base64","./aria subghz raw formats 1"),
 RUN(SUBGHZ,"All payload views","All representations of latest capture","./aria subghz raw all 1"),
 EDIT(SUBGHZ,"Capture frequency filter","Frequency MHz or clear","./aria subghz raw filter %s",TEXT),
 RUN(SUBGHZ,"Analyze latest","Timing and capture quality","./aria subghz raw analyze"),
 RUN(SUBGHZ,"Identify latest","Protocol evidence and confidence","./aria subghz raw id"),
 EDIT(SUBGHZ,"Decode HEX","Enter a payload to decode","./aria subghz raw decode %s",HEX_INPUT),
 EDIT(SUBGHZ,"Identify HEX","Example: 433.92 AABBCC","./aria subghz raw id %s",TEXT),
 RUN(SUBGHZ,"Protocol library","Supported decoders and brands","./aria subghz protocols"),
 PICK(SUBGHZ,"FSK profile","Automatic / WH31 / raw receive","./aria subghz fsk %s",TEXT,"auto|wh31|raw|profiles"),
 RUN(SUBGHZ,"Save raw snapshot","Preserve retained samples","./aria subghz raw save"),
 ASK(SUBGHZ,"Clear raw captures","Remove retained raw history","./aria subghz raw clear"),
 RUN(LORA,"Receiver details","Actual baud, frequency and packets","./aria lora list"),
 RUN(LORA,"Start reception","Listen through DX-LR22 UART","./aria lora scan on"),
 RUN(LORA,"Stop reception","Pause UART reception","./aria lora scan off"),
 RUN(LORA,"Original evidence","Retained UART bytes","./aria evidence lora limit 4"),
 RUN(DRAGON,"BLE MITM","Relay connectable GATT peripheral to your iPhone app","ui.blelab"),
 RUN(DRAGON,"MITM status","Relay connection and statistics","./aria dragon mitm status"),
 RUN(DRAGON,"Stop MITM","Stop GATT relay","./aria dragon mitm stop"),
 RUN(DRAGON,"Nearby devices","Names, vendors and signal strength","ui.devices"),
 PICK(DRAGON,"Start scan","Seconds; 0 is continuous","./aria dragon scan %s",NUMBER,"0|10|30|60"),
 RUN(DRAGON,"Radio status","Internal and CSR radio health","./aria dragon radio status"),
 RUN(DRAGON,"Radio list","Available Bluetooth interfaces","./aria dragon radio list"),
 RUN(DRAGON,"Initialize CSR","Initialize attached USB dongle","./aria dragon radio init csr"),
 PICK(DRAGON,"Select radio","Choose internal or USB CSR","./aria dragon radio select %s",TEXT,"internal|csr"),
 PICK(DRAGON,"Dual radio","Use both radios together","./aria dragon radio dual %s",TEXT,"on|off"),
 PICK(DRAGON,"Lock channel","BLE advertising channel","./aria dragon channel lock %s",NUMBER,"37|38|39"),
 RUN(DRAGON,"Hop channel","Advance advertising channel","./aria dragon channel hop"),
 PICK(DRAGON,"CSR channel","Set external radio channel","./aria dragon radio channel csr %s",NUMBER,"37|38|39"),
 PICK(DRAGON,"Internal channel","Set channel metadata hint; scan visits 37/38/39","./aria dragon radio channel internal %s",NUMBER,"37|38|39"),
 RUN(DRAGON,"Stop scan","Pause Dragon scan","./aria dragon scan stop"),
 EDIT(DRAGON,"Capture target","Capture advertisements for the current observed MAC","./aria dragon sniff %s",MAC),
 RUN(DRAGON,"Target capture status","Target identity, live counts and original advertising HEX","ui.blecapture"),
 RUN(DRAGON,"Stop target capture","Remove target filter","./aria dragon sniff stop"),
 RUN(DRAGON,"Capture statistics","Packets, buffers and radios","./aria dragon stats"),
 RUN(DRAGON,"GPS state","Dragon GPS receiver","./aria dragon gps"),
 ASK(DRAGON,"Save PCAP","Save and drain buffer to mounted SD","./aria dragon save auto"),
 EDIT(DRAGON,"Save PCAP as","SD path for capture","./aria dragon save %s",TEXT),
 ASK(DRAGON,"Clear packet buffer","Remove buffered Dragon packets","./aria dragon clear"),
 RUN(DRAGON,"Command reference","All Dragon controls","./aria dragon help"),
 RUN(TRACK,"Wi-Fi devices","Select a MAC to build sighting scenes","ui.trackpick wifi"),
 RUN(TRACK,"Bluetooth devices","Select a BLE address to track","ui.trackpick ble"),
 RUN(TRACK,"Sub-GHz devices","Select verified decoded device IDs","ui.trackpick subghz"),
 RUN(TRACK,"LoRa devices","Requires decoded device identities","ui.trackpick lora"),
 RUN(TRACK,"Scene status","Windows, closest signal and capture health","ui.track asset"),
 RUN(TRACK,"Arm monitoring","Resume selected device tracking","ui.track arm"),
 RUN(TRACK,"Disarm monitoring","Pause selected device tracking","ui.track disarm"),
 RUN(TRACK,"Download scenes","Export runtime scenes and captured bytes","./aria download on"),
 RUN(CAPTURES,"Sub-GHz raw capture","Latest event/frame and complete authoritative waveform HEX","ui.raw"),
 RUN(CAPTURES,"Replay samples","Browse retained raw samples; transmission requires confirmation","ui.replay"),
 RUN(CAPTURES,"BLE target capture","Selected MAC, received advertisement HEX and live counters","ui.blecapture"),
 RUN(CAPTURES,"Export captures","Download existing captured evidence as JSON","./aria download on"),
 RUN(LINK,"Link status","ESP-NOW connection and counters","./aria lr status"),
 EDIT(LINK,"Set peer","Enter peer MAC address","./aria lr peer %s",MAC),
 EDIT(LINK,"Send message","Message to configured peer","./aria lr send \"%s\"",TEXT),
 RUN(LINK,"Test link","Send existing link test","./aria lr test"),
 RUN(LOGS,"Session status","Capture counts and storage","./aria log status"),
 RUN(LOGS,"Wi-Fi download","Connect iPhone; download JSON","./aria download on"),
 RUN(LOGS,"Resume scanning","Leave download mode; resume radios","./aria download resume"),
 RUN(LOGS,"Save session","Snapshot to PSRAM until reboot","./aria log save"),
 RUN(LOGS,"Inspect session","Read saved session text","./aria log dump"),
 RUN(LOGS,"Capture summaries","All radio capture metadata","./aria captures"),
 RUN(LOGS,"Evidence health","Retained bytes and dropped frames","./aria evidence status"),
 EDIT(LOGS,"Older Wi-Fi evidence","Example: before 123 limit 4","./aria wifi frames %s",TEXT),
 EDIT(LOGS,"Older BLE evidence","Example: before 123 limit 4","./aria evidence ble %s",TEXT),
 EDIT(LOGS,"Older LoRa evidence","Example: before 123 limit 4","./aria evidence lora %s",TEXT),
 RUN(SYSTEM,"System health","Heap, PSRAM, uptime and temperature","./aria system info"),
 RUN(SYSTEM,"Hardware capabilities","Real radio features and state","./aria capabilities"),
 RUN(SYSTEM,"Access point status","SSID, channel and clients","./aria ap status"),
 RUN(SYSTEM,"Start access point","Bring up ARIA Wi-Fi","./aria ap on"),
 RUN(SYSTEM,"Restart access point","Restart Wi-Fi beacons","./aria ap restart"),
 EDIT(SYSTEM,"Access point name","Rename ARIA Wi-Fi","./aria ap ssid \"%s\"",TEXT),
 RUN(SYSTEM,"Touch calibration","Tap three targets","ui.calibrate"),
 RUN(SYSTEM,"Accent color","Choose cyan, violet or amber","ui.theme"),
 RUN(SYSTEM,"Command reference","All unified firmware commands","./aria system help"),
 EDIT(SYSTEM,"Command console","Enter any ARIA command","%s",COMMAND),
 ASK(SYSTEM,"Restart device","Reboot; RAM captures will be lost","./aria system reset")
};
#undef RUN
#undef EDIT
#undef PICK
#undef ASK
constexpr size_t actionCount=sizeof(actions)/sizeof(actions[0]);
constexpr size_t toolCount=sizeof(tools)/sizeof(tools[0]);
inline size_t groupCount(Group g) { size_t n=0; for(const auto& a:actions) if(a.group==g) ++n; return n; }
inline int actionIndex(Group g,size_t position) {
  for(size_t i=0;i<actionCount;++i) if(actions[i].group==g) { if(position==0) return (int)i; --position; }
  return -1;
}
}
