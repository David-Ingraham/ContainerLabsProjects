pub fn str_ip_to_u32(ip: &str)-> u32{

 //  let mut octets: Vec<&str> = ip.split(".").collect();
     // ** wasting space by creating the octect vecotr ****
    //let mut u8_octect_vec: Vec<u8> = vec![];

    //for octet in octets{
    //    u8_octect_vec.push(octet.parse().unwrap());
    //}

    let u8_octect_vec: Vec<u8> = ip.split(".")  // creating one vector from the ip string
        .map(|octet| octet.parse().unwrap())
        .collect(); // could use .collect()::<Vec<u8>>() turbofish but i specify the type in vector declaration / asignment

    let a = u8_octect_vec[0];
    let b = u8_octect_vec[1];
    let c = u8_octect_vec[2];
    let d = u8_octect_vec[3];

    let ip_u32 = (a as u32) << 24 
    | (b as u32) << 16 
    | (c as u32) << 8  
    | (d as u32);
    //since each letter is a u8, think about pushing a 8 bit number onto a u32 from the right
    // (a <<24 ) the first bit of a would be at the 8th bit from the right of the u32, so shifting it 24 bits places 
    //the first bit of a is no at 24 + 8 = 32nd bit position in the u32. so on with each octet
    //each expression containerd in the () is a u32, so we use the | which is the or operator. 
    // this is inclusive or, so if either it is 1 the results is 1. when doing bit operations on multi bit numbers, it goes bit by bit
    //11000000_00000000_00000000_00000000  (a as u32 << 24)
    //| 00000000_10101000_00000000_00000000  (b as u32 << 16)
    //| 00000000_00000000_00000001_00000000  (c as u32 << 8)
    //| 00000000_00000000_00000000_00000001  (d as u32)
    //= 11000000_10101000_00000001_00000001  (192.168.1.1)

    return ip_u32;
}

pub fn u32_to_str_ip(ip_u32: u32)-> String{

    let str_ip = format!("{}.{}.{}.{}", 
    (ip_u32 >> 24) & 0xFF, // taking first 1/4th of the bits from the u32 subnet, shifting that first bit in (starting at 8th position)
                               //to the right 24 places so it ends up 32 from the right, or at the begining of the u32. 
                               // the & OxFF turns the remaining 24 bits in to 0. Ox means hexadecimal, FF is 1^16 + 2^16 = 256 or 11111111 in binary
                               // & (and) bit operation against all zeros turns operand into all zeros 
    (ip_u32 >> 16) & 0xFF, // same process but starting 16 bits from the right to not undo the work in the first octet
    (ip_u32 >> 8) & 0xFF,
    ip_u32 & 0xFF);


    return str_ip;
}