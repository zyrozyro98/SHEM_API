require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const productsRouter = require('./routes/products');
const ordersRouter = require('./routes/orders');
const paymentsRouter = require('./routes/payments');
const adminRouter = require('./routes/admin');
const deliveryRouter = require('./routes/delivery');
const notificationsRouter = require('./routes/notifications');
const mediaRouter = require('./routes/media');

const app = express();
app.use(cors());
app.use(bodyParser.json());

app.use('/products', productsRouter);
app.use('/orders', ordersRouter);
app.use('/payments', paymentsRouter);
app.use('/admin', adminRouter);
app.use('/delivery', deliveryRouter);
app.use('/notifications', notificationsRouter);
app.use('/media', mediaRouter);

app.get('/', (req, res) => res.json({ ok: true, message: 'She M backend API' }));

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`API server listening on ${PORT}`));
