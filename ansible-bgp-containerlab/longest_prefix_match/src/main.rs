mod subnet_calc;
mod ip_conversions;
mod pick_route;
mod read_routes;
mod read_packet;


fn test_read_packet() {

    loop {
        match read_packet::read_packet() {
            Ok(packet_info) => {
                println!("Got packet to: {}", packet_info.destination_ip);
              
            }
            Err(e) => eprintln!("Error: {}", e),
        }
    }
}

#[tokio::main] //needs to be here and not in read_routes bc this set the fintinn underneath as the entry point
async fn test_read_routes() {
    let mut route_table = read_routes::read_routes().await;
    //while let Some(route) = routes.try_next().await.unwrap() {
        //println!("{:?}", route);
    //}
    match route_table {
        Ok(routes) => {
            println!("Routes: {:?}", routes);
        }
        Err(e) => {
            eprintln!("Error reading routes: {}", e);
        }
    }
}

//turn tests for read_routes and read_apckets ito fucniotns 

fn main() {

    test_read_packet();

    println!("done");
    


}
