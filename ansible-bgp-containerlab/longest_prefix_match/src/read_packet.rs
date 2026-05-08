use nfq::{Queue, Verdict, Message};
use std::net::Ipv4Addr;

pub struct PacketInfo {
    pub destination_ip: String,
    pub source_ip: String,
}

pub fn read_packet() -> Result<PacketInfo, Box<dyn std::error::Error>> {
    let mut queue = Queue::open()?;
    queue.bind(0)?;
    
    let mut msg = queue.recv()?;
    let packet_info = extract_ip_info(&msg)
        .ok_or("Failed to parse packet")?;
    
    msg.set_verdict(Verdict::Accept);
    queue.verdict(msg)?;
    
    Ok(packet_info)
}

fn extract_ip_info(msg: &Message) -> Option<PacketInfo> {
    let payload = msg.get_payload();
    
    if payload.len() < 20 {
        return None;
    }
    
    let version = (payload[0] >> 4) & 0x0F;
    if version != 4 {
        return None;
    }
    
    let src_bytes = [payload[12], payload[13], payload[14], payload[15]];
    let dst_bytes = [payload[16], payload[17], payload[18], payload[19]];
    
    let source_ip = Ipv4Addr::from(src_bytes).to_string();
    let destination_ip = Ipv4Addr::from(dst_bytes).to_string();
    
    Some(PacketInfo {
        source_ip,
        destination_ip,
    })
}
