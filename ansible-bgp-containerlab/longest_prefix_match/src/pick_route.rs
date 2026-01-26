use crate::subnet_calc;
use crate::ip_conversions::u32_to_str_ip;
//use crate::routes::Route;

pub struct Route {
    pub ip: String,
    pub mask: String,
    pub port: String,
}

pub struct Packet<'a> {
    pub destination_ip: &'a str,
    pub destination_mask: &'a str,
}

pub fn pick_route<'a>(packet: &Packet, routing_table: &'a Vec<Route>) -> Option<&'a Route> { // Option<> >this lets me return none. i think this has somhting to do with enums?
                                                                 //Option<T> is a enum that ships with the prelude.variants include Some and None

    let candidates: Vec<&Route> = routing_table.iter()
    .filter(|route| route.ip == u32_to_str_ip(subnet_calc::calc_subnet(&packet.destination_ip, &packet.destination_mask)))
    .collect();

    if candidates.is_empty() {
        return None; 
    }


    
    candidates.iter()
         .max_by_key(|route| route.mask.parse::<u32>().unwrap())
         .copied()
    
}