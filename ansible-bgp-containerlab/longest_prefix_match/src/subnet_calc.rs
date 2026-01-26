//broadast calc would also be cool


use crate::ip_conversions::str_ip_to_u32; //only main.rs should use mod keyword

pub fn calc_subnet(ip: &str, mask: &str)-> u32 {

    let ip_u32 = str_ip_to_u32(ip);
  
   

   let prefix_len: u8 = mask.parse().unwrap();

   let u32_mask = !((1 << (32 - prefix_len)) -1);

   // (1 << (32 - mask)) bits shfits 1, (single bit) 32- mask bumber of places to the left 
   // subtracting 1 from that tunrs all the zeros to left into 1, and tunr the original 1 into a zero, leaving you with a run of 32 - mask lenght of zeros
   // taking the inverse with ! of that so that we get a run of 1 of mask lenght follow by a run of 32 - mask lenght of zeros


    //let subnet_u32 = ip_u32 & mask; //i dont have to use return statment becuase the last expression is the return value? would be an expression 
    //if i dind thave the semi colon 

    ip_u32 & u32_mask  // no semi colon, just the return value


}


