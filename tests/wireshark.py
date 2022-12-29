import argparse
import os
import sys
import scapy.all as scapy
from scapy.utils import RawPcapReader
from scapy.layers.l2 import Ether
from scapy.layers.inet import IP, TCP
from bitstring import BitArray, BitStream, ReadError
import os

def process_pcap(file_name):
	print('Opening {}...'.format(file_name))
	
	count = 0	
	for (pkt_data, pkt_metadata,) in RawPcapReader(file_name):
		count += 1
	
		#print("LEN: %s" % len(pkt_data))
		if (len(pkt_data) != 449):
			continue
		
		process_packet(pkt_data)

	print('{} contains {} packets'.
		  format(file_name, count))

def binaryToDecimal(binary): 
    binary1 = binary 
    decimal, i, n = 0, 0, 0
    while(binary != 0): 
        dec = binary % 10
        decimal = decimal + dec * pow(2, i) 
        binary = binary//10
        i += 1
    return decimal 

DT_BYTE = 1
DT_SHORT = 2
DT_FLOAT = 4
DT_INTEGER = 8
DT_ANGLE = 16
DT_TIMEWINDOW_8	= 32
DT_TIMEWINDOW_BIG = 64
DT_STRING = 128
DT_SIGNED = 256

class Delta:
	name = ''
	deltaType = 0
	bits = 0
	multiplier = 1
	
	def __init__(self, name, deltaType, bits, multiplier):
		self.name = name
		self.deltaType = deltaType
		self.bits = bits
		self.multiplier = multiplier

entity_state_t = [
	Delta( 'animtime', DT_TIMEWINDOW_8, 8, 1.0 ),
	Delta( 'frame', DT_FLOAT, 10, 4.0 ),
	Delta( 'origin[0]', DT_SIGNED | DT_FLOAT, 24, 8.0 ),
	Delta( 'angles[0]', DT_ANGLE, 16, 1.0 ),
	Delta( 'angles[1]', DT_ANGLE, 16, 1.0 ),
	Delta( 'origin[1]', DT_SIGNED | DT_FLOAT, 24, 8.0 ),
	Delta( 'origin[2]', DT_SIGNED | DT_FLOAT, 24, 8.0 ),
	Delta( 'sequence', DT_INTEGER, 8, 1.0 ),
	Delta( 'modelindex', DT_INTEGER, 13, 1.0 ),
	Delta( 'movetype', DT_INTEGER, 4, 1.0 ),
	Delta( 'solid', DT_SHORT, 3, 1.0 ),
	Delta( 'mins[0]', DT_SIGNED | DT_FLOAT, 16, 8.0 ),
	Delta( 'mins[1]', DT_SIGNED | DT_FLOAT, 16, 8.0 ),
	Delta( 'mins[2]', DT_SIGNED | DT_FLOAT, 16, 8.0 ),
	Delta( 'maxs[0]', DT_SIGNED | DT_FLOAT, 16, 8.0 ),
	Delta( 'maxs[1]', DT_SIGNED | DT_FLOAT, 16, 8.0 ),
	Delta( 'maxs[2]', DT_SIGNED | DT_FLOAT, 16, 8.0 ),
	Delta( 'endpos[0]', DT_SIGNED | DT_FLOAT, 13, 1.0 ),
	Delta( 'endpos[1]', DT_SIGNED | DT_FLOAT, 13, 1.0 ),
	Delta( 'endpos[2]', DT_SIGNED | DT_FLOAT, 13, 1.0 ),
	Delta( 'startpos[0]', DT_SIGNED | DT_FLOAT, 13, 1.0 ),
	Delta( 'startpos[1]', DT_SIGNED | DT_FLOAT, 13, 1.0 ),
	Delta( 'startpos[2]', DT_SIGNED | DT_FLOAT, 13, 1.0 ),
	Delta( 'impacttime', DT_TIMEWINDOW_BIG, 13, 100.0 ),
	Delta( 'starttime', DT_TIMEWINDOW_BIG, 13, 100.0 ),
	Delta( 'weaponmodel', DT_INTEGER, 13, 1.0 ),
	Delta( 'owner', DT_INTEGER, 5, 1.0 ),
	Delta( 'effects', DT_INTEGER, 16, 1.0 ),
	Delta( 'eflags', DT_INTEGER, 1, 1.0 ),
	Delta( 'angles[2]', DT_ANGLE, 16, 1.0 ),
	Delta( 'colormap', DT_INTEGER, 16, 1.0 ),
	Delta( 'framerate', DT_SIGNED | DT_FLOAT, 8, 16.0 ),
	Delta( 'skin', DT_SHORT | DT_SIGNED, 13, 1.0 ),
	Delta( 'controller[0]', DT_BYTE, 8, 1.0 ),
	Delta( 'controller[1]', DT_BYTE, 8, 1.0 ),
	Delta( 'controller[2]', DT_BYTE, 8, 1.0 ),
	Delta( 'controller[3]', DT_BYTE, 8, 1.0 ),
	Delta( 'blending[0]', DT_BYTE, 8, 1.0 ),
	Delta( 'blending[1]', DT_BYTE, 8, 1.0 ),
	Delta( 'body', DT_INTEGER, 8, 1.0 ),
	Delta( 'rendermode', DT_INTEGER, 8, 1.0 ),
	Delta( 'renderamt', DT_INTEGER, 8, 1.0 ),
	Delta( 'renderfx', DT_INTEGER, 8, 1.0 ),
	Delta( 'scale', DT_FLOAT, 16, 256.0 ),
	Delta( 'rendercolor.r', DT_BYTE, 8, 1.0 ),
	Delta( 'rendercolor.g', DT_BYTE, 8, 1.0 ),
	Delta( 'rendercolor.b', DT_BYTE, 8, 1.0 ),
	Delta( 'aiment', DT_INTEGER, 11, 1.0 ),
	Delta( 'basevelocity[0]', DT_SIGNED | DT_FLOAT, 16, 8.0 ),
	Delta( 'basevelocity[1]', DT_SIGNED | DT_FLOAT, 16, 8.0 ),
	Delta( 'basevelocity[2]', DT_SIGNED | DT_FLOAT, 16, 8.0 ),
	Delta( 'playerclass', DT_INTEGER, 1, 1.0 ),
	Delta( 'fuser1', DT_FLOAT, 8, 1.0 ),
	Delta( 'fuser2', DT_FLOAT, 8, 1.0 ),
	Delta( 'iuser1', DT_INTEGER, 8, 1.0 ),
	Delta( 'gaitsequence', DT_INTEGER, 8, 1.0 )
]

super_string = ""
replay_txt = open('replay.txt', 'w')
replay_txt.write('array<array<uint8>> replay = {')

def process_voice_packet(data):
	idx = data.find(b'\x35')
	if idx != -1:
		#os.system('cls' if os.name == 'nt' else 'clear')
		deltaPacket = BitStream(data[idx+1:])
		playerIdx = deltaPacket.read('uintle:8')
		length = deltaPacket.read('uintle:16')
		
		if playerIdx != 0:
			return
		
		print("Parse svc_voicedata, idx %d, len %d" % (playerIdx, length) )
		
		byte_str = "\t{"
		for x in range(0, length):
			byte_str += "%d, " % deltaPacket.read('uintle:8')
			
		byte_str = byte_str[:-2] + "},"
		replay_txt.write(byte_str + "\n")
		
		print(byte_str)
		
def process_packet(data):

	idx = data.rfind(b'\x29')
	if idx != -1:
		os.system('cls' if os.name == 'nt' else 'clear')
		deltaPacket = BitStream(data[idx+1:])
		print("Parse svc_deltapacketentities(%s): %s" % (len(deltaPacket)+1, deltaPacket[32+7+3:]))
		print("Full packet: %s" % deltaPacket)
		numEntities = deltaPacket.read('uintle:16')
		print("    Entity Count: %s" % numEntities)
		
		if True:
			oldpacket = deltaPacket.read('uintle:16')
			print("    Old Packet:   %s" % oldpacket)
			while True:
				entindexBits = deltaPacket.read('bin:6')
				entindexDec = binaryToDecimal(int(entindexBits))
				
				# uses more bits for index only if the next bit is SET
				hasLongerIdx = deltaPacket.read('bin:1')
				if hasLongerIdx == '1':
					unusedBits = deltaPacket.read('bin:2')
					addBits = deltaPacket.read('bin:13') # bottom 6 bits are never set so may also be used for something else
					addDec = binaryToDecimal(int(addBits))
					print("    Entity Idx:   %s (%s) + %s (%s) = %s" % (entindexBits, entindexDec, addBits, addDec, entindexDec + addDec))
					if (unusedBits != '00'):
						print("    UNUSED BITS ARE ACTUALLY USED!!!!: %s" % unusedBits)
				else:
					print("    Entity Idx:   %s (%s)" % (entindexBits, entindexDec))
				
				'''
				removeType = binaryToDecimal(int(deltaPacket.read('bin:2')))
				print("    RemoveType:   %s" % (removeType))
				if (removeType != 0):
					print("ZOMG ENT REMOVED")
				'''
				
				'''
				entityTypeChanged = int(deltaPacket.read('bin:1'))
				print("    ChangeType:   %s" % (entityTypeChanged))
				if (entityTypeChanged == 1):
					newEntityType = binaryToDecimal(int(deltaPacket.read('bin:2')))
					print("WOW NEW ENTITY TYPE")
				'''
				
				'''
				changed = ''
				b = 0
				while True:
					b += 1
					if (b % 8 == 0):
						changed += ' '
					try:
						bit = deltaPacket.read('bin:1')
						
						changed += '\033[92m1' if bit == '1' else '\033[0m0'
					except:
						break
					
				print("    changed:      %s" % changed)
				break
				'''
				
				'''
				for idx, delta in enumerate(entity_state_t):
					changed = int(deltaPacket.read('bin:1'))
					
					if idx == 2 or idx == 3 or idx == 4:
						changed = 1 - changed # this bit is inverted for some reason?
					
					if (changed):
						print("    %-13s CHANGED" % (delta.name + ":"))
						break
					else:
						print("    %-13s (no delta)" % (delta.name + ":"))
				'''
				
				skip = deltaPacket.read('bin:9')
				
				zDec_0 = deltaPacket.read('uint:4') # only top 4 bits are used
				unused = deltaPacket.read('bin:4')
				zDec_1 = deltaPacket.read('uint:8')
				zDec_2 = deltaPacket.read('uint:8')
				#zDec = (zDec_0 << 16) + (zDec_1 << 8) + (zDec_2)
				zDec = (zDec_2 << 16) + (zDec_1 << 8) + (zDec_0 << 4)
				
				zSign = (zDec_0 >> 4) & 0x1
				if (zSign != 0):
					zDec = -zDec
				
				
				#zDec = deltaPacket.read('intle:24')
				
				#if signBit == '1':
				#	zDec = -( (1 << 22) - zDec )
				zDec = (zDec >> 5) / 8.0
				
				print("    Skip:         %s" % (skip))
				print("    Origin Z:     %s (%s) (unused = %s)" % (zDec, hex(zSign).replace("0x",""), unused))
				
				
				try:
					next = deltaPacket.read('hex:16')
					print("    Next:         %s" % next)
				except ReadError as e:
					pass
				break

def process_sniffed_packets(packet):
	payload = bytes(packet.payload.payload)
	#print("WOW %s = %s" % (type(payload), dir(payload)))
	#print("WOW %s" % payload)
	#print("WOW2 %s" % payload[0])
	try:
		#process_packet(payload)
		process_voice_packet(payload)
	except Exception as e:
		print("Failed to parse packet: %s" % e)

def sniff():
	#scapy.sniff(iface='Software Loopback Interface 1', filter="udp and port 27015", store=False, prn=process_sniffed_packets)
	scapy.sniff(iface='Ethernet', filter="udp and port 27015", store=False, prn=process_sniffed_packets)
		


sniff()
#process_pcap('test.pcap')