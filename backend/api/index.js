require('dotenv').config();
const express = require('express');
const bodyParser = require('body-parser');
const cors = require('cors');
const productsRouter = require('./routes/products');
const productSearchRouter = require('./routes/product_search');
const ordersRouter = require('./routes/orders');
const paymentsRouter = require('./routes/payments');
const authRouter = require('./routes/auth');
const adminRouter = require('./routes/admin');
const deliveryRouter = require('./routes/delivery');
const notificationsRouter = require('./routes/notifications');
const mediaRouter = require('./routes/media');
const accountsRouter = require('./routes/accounts');
const appUpdateRouter = require('./routes/app_update');
const promotionsRouter = require('./routes/promotions').router;
const googleSignInConfigRouter = require('./routes/google_sign_in_config');
const healthRouter = require('./routes/health');
const databaseRouter = require('./routes/database');

const app = express();
app.set('trust proxy', 1);
app.use(cors());
app.use(bodyParser.json({ limit: '10mb' }));

app.use('/products', productsRouter);
app.use('/product-search', productSearchRouter);
app.use('/orders', ordersRouter);
app.use('/payments', paymentsRouter);
app.use('/auth', authRouter);
app.use('/admin', adminRouter);
app.use('/delivery', deliveryRouter);
app.use('/notifications', notificationsRouter);
app.use('/media', mediaRouter);
app.use('/accounts', accountsRouter);
app.use('/app-update', appUpdateRouter);
app.use('/promotions', promotionsRouter);
app.use('/config', googleSignInConfigRouter);
app.use('/health', healthRouter);
app.use('/database', databaseRouter);

app.get('/', (req, res) => res.json({ ok: true, message: 'She M backend API' }));

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => console.log(`API server listening on ${PORT}`));
