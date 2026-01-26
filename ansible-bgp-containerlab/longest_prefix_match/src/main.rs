mod subnet_calc;
mod ip_conversions;
mod pick_route;
mod read_routes;


#[tokio::main] //needs to be here and not in read_routes bc this set the fintinn underneath as the entry point
async fn main() {
    
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
