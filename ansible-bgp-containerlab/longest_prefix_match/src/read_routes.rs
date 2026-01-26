use futures::stream::TryStreamExt;
use rtnetlink::{new_connection, IpVersion};
use netlink_packet_route::route::RouteMessage;

pub async fn read_routes() -> Result<Vec<RouteMessage>, Box<dyn std::error::Error>> {
    

    let (connection, handle, _) = match new_connection() {

        Ok((connection, handle, _))=> (connection, handle, ()),
        Err(e) => {
            eprintln!("Error: {}", e);
            return Err(Box::new(e));
        }
    };
    
    tokio::spawn(connection);
    let mut routes= handle.route().get(IpVersion::V4).execute();
    let mut route_table = Vec::new();

    loop {
        match routes.try_next().await {
            Ok(Some(route)) => {
                //println!("Route: {:?}", route);
                route_table.push(route);
            }
            Ok(None) => {
                //println!("No more routes");
                break;  // End of stream
            }
            Err(e) => {
                eprintln!("Error reading route: {}", e);
                return Err(Box::new(e));
                
            }
        }
    }
    Ok(route_table)
    //while let Some(route) = routes.try_next().await.unwrap() {
      //  println!("{:?}", route);
    //}
}